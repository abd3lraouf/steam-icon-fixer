#requires -version 5.1
# =============================================================================
#  Steam Shortcut Fixer v2.0 - GUI
#  by abd3lraouf
#
#  Scans Steam libraries, shows your games with their real icons / artwork,
#  and creates or repairs Desktop + Start Menu shortcuts (.url) with real
#  .ico icons downloaded from Steam's CDN. No admin, no dependencies.
#
#  Launch:  "Steam Shortcut Fixer GUI.cmd"  or
#           powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ThisFile.ps1
# =============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
try {
    Add-Type -Namespace SSF -Name Native -MemberDefinition @'
[DllImport("shell32.dll")] public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
    [void][SSF.Native]::SetProcessDPIAware()
} catch { }

# =============================================================================
#  UI toolkit - custom dark controls (GDI+ owner drawn, no WinForms chrome)
# =============================================================================
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace SSF
{
    // ---------------------------------------------------------------- palette
    public static class Pal
    {
        // Steam's own palette, pushed deeper: near-black navy ground, the
        // classic #66C0F4 blue as the accent, aqua as its gradient partner.
        public static Color Bg          = Color.FromArgb( 11,  16,  24);
        public static Color Surface     = Color.FromArgb( 20,  28,  40);
        public static Color Elevated    = Color.FromArgb( 27,  40,  56);
        public static Color Field       = Color.FromArgb( 14,  20,  30);
        public static Color Border      = Color.FromArgb( 42,  71,  94);
        public static Color BorderSoft  = Color.FromArgb( 29,  43,  60);
        public static Color Text        = Color.FromArgb(206, 219, 230);
        public static Color Dim         = Color.FromArgb(143, 163, 184);
        public static Color Faint       = Color.FromArgb(106, 126, 147);
        public static Color Accent      = Color.FromArgb(102, 192, 244);
        public static Color AccentHot   = Color.FromArgb(158, 220, 255);
        public static Color AccentDeep  = Color.FromArgb( 23, 105, 170);
        public static Color Accent2     = Color.FromArgb( 55, 198, 214);
        public static Color AccentDark  = Color.FromArgb(  8,  14,  22);
        public static Color Ok          = Color.FromArgb(124, 195,  68);
        public static Color Warn        = Color.FromArgb(240, 181,  74);
        public static Color Err         = Color.FromArgb(226,  94,  94);
        public static Color RowHover    = Color.FromArgb( 23,  33,  46);
        public static Color RowSel      = Color.FromArgb( 22,  50,  74);
        public static Color RowLine     = Color.FromArgb( 26,  37,  52);

        public static Font FUI    = new Font("Segoe UI", 9.25f);
        public static Font FUIB   = new Font("Segoe UI Semibold", 9.25f);
        public static Font FTitle = new Font("Segoe UI Semibold", 16.5f);
        public static Font FSmall = new Font("Segoe UI", 8.25f);
        public static Font FRow   = new Font("Segoe UI Semibold", 10f);
        public static Font FPill  = new Font("Segoe UI Semibold", 8f);
        public static Font FHead  = new Font("Segoe UI Semibold", 7.75f);
        public static Font FMono  = new Font("Consolas", 9f);
        public static Font FGlyph = new Font("Segoe MDL2 Assets", 10f);
    }

    // ------------------------------------------------------------- gdi+ helpers
    public static class Gfx
    {
        public static GraphicsPath Round(Rectangle r, int rad)
        {
            GraphicsPath p = new GraphicsPath();
            if (rad <= 0) { p.AddRectangle(r); return p; }
            int d = rad * 2;
            if (d > r.Width)  d = r.Width;
            if (d > r.Height) d = r.Height;
            if (d <= 0) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
        public static void Fill(Graphics g, Rectangle r, int rad, Color c)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            using (GraphicsPath p = Round(r, rad))
            using (SolidBrush b = new SolidBrush(c)) g.FillPath(b, p);
        }
        public static void Stroke(Graphics g, Rectangle r, int rad, Color c, float w)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            using (GraphicsPath p = Round(r, rad))
            using (Pen pen = new Pen(c, w)) g.DrawPath(pen, p);
        }
        public static Color Mix(Color fg, Color bg, int alpha)
        {
            int r  = (fg.R * alpha + bg.R * (255 - alpha)) / 255;
            int g2 = (fg.G * alpha + bg.G * (255 - alpha)) / 255;
            int b  = (fg.B * alpha + bg.B * (255 - alpha)) / 255;
            return Color.FromArgb(r, g2, b);
        }
        public static void Check(Graphics g, Rectangle b, Color c)
        {
            using (Pen p = new Pen(c, 2f))
            {
                p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
                float x = b.X, y = b.Y, w = b.Width, h = b.Height;
                g.DrawLines(p, new PointF[] {
                    new PointF(x + w * 0.24f, y + h * 0.52f),
                    new PointF(x + w * 0.43f, y + h * 0.71f),
                    new PointF(x + w * 0.77f, y + h * 0.30f) });
            }
        }
    }

    // ------------------------------------------------------------------ grain
    // One tileable monochrome noise tile, reused by every surface that wants
    // texture. Alpha stays low so it reads as film grain, not dirt.
    public static class Grain
    {
        public static TextureBrush Fine;
        public static TextureBrush Soft;

        static Grain()
        {
            Fine = Make(192, 9);    // the CTA wash
            Soft = Make(192, 4);    // large surfaces
        }
        // 1px monochrome speckle, mostly light, alpha capped low - at 100% zoom
        // it reads as a slight tooth on the surface, never as visible noise.
        private static TextureBrush Make(int size, int amp)
        {
            Bitmap bmp = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            Random rnd = new Random(20240517);
            for (int y = 0; y < size; y++)
            {
                for (int x = 0; x < size; x++)
                {
                    int a = rnd.Next(0, amp);
                    int v = (rnd.Next(0, 3) == 0) ? 0 : 255;
                    bmp.SetPixel(x, y, Color.FromArgb(a, v, v, v));
                }
            }
            TextureBrush tb = new TextureBrush(bmp);
            tb.WrapMode = WrapMode.Tile;
            return tb;
        }
        public static void Apply(Graphics g, GraphicsPath p, bool soft)
        {
            g.FillPath(soft ? Soft : Fine, p);
        }
        public static void Apply(Graphics g, Rectangle r, int rad, bool soft)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            using (GraphicsPath p = Gfx.Round(r, rad)) g.FillPath(soft ? Soft : Fine, p);
        }
    }

    // ------------------------------------------------------------------- link
    public class SsfLink : Control
    {
        private bool hot;
        public string Url = "";
        public Color Normal = Pal.Dim;
        public Color Hover = Pal.AccentHot;

        public SsfLink()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Font = Pal.FSmall;
            Cursor = Cursors.Hand;
            Height = 18;
            TabStop = false;
        }
        protected override void OnTextChanged(EventArgs e)
        {
            Width = TextRenderer.MeasureText(Text, Font).Width + 2;
            base.OnTextChanged(e);
        }
        protected override void OnMouseEnter(EventArgs e) { hot = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hot = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Color c = hot ? Hover : Normal;
            TextRenderer.DrawText(g, Text, Font, new Rectangle(0, 0, Width, Height), c,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            if (hot)
            {
                int w = TextRenderer.MeasureText(Text, Font).Width;
                using (Pen p = new Pen(c)) g.DrawLine(p, 0, Height - 3, w - 3, Height - 3);
            }
        }
    }

    // ------------------------------------------------------------ window chrome
    public static class Chrome
    {
        [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
        [DllImport("uxtheme.dll", EntryPoint = "#135")] private static extern int SetPreferredAppMode(int mode);
        [DllImport("uxtheme.dll", EntryPoint = "#136")] private static extern void FlushMenuThemes();
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] private static extern int SetWindowTheme(IntPtr h, string app, string id);

        private static int Ref(Color c) { return c.R | (c.G << 8) | (c.B << 16); }

        public static void DarkApp()
        {
            try { SetPreferredAppMode(2); FlushMenuThemes(); } catch { }
        }
        public static void DarkWindow(IntPtr h)
        {
            int one = 1;
            try { DwmSetWindowAttribute(h, 20, ref one, 4); } catch { }
            try { DwmSetWindowAttribute(h, 19, ref one, 4); } catch { }
            int round = 2;
            try { DwmSetWindowAttribute(h, 33, ref round, 4); } catch { }
            int cap = Ref(Pal.Bg);
            try { DwmSetWindowAttribute(h, 35, ref cap, 4); } catch { }
            int bor = Ref(Pal.BorderSoft);
            try { DwmSetWindowAttribute(h, 34, ref bor, 4); } catch { }
            int txt = Ref(Pal.Text);
            try { DwmSetWindowAttribute(h, 36, ref txt, 4); } catch { }
        }
        public static void DarkScroll(IntPtr h)
        {
            try { SetWindowTheme(h, "DarkMode_Explorer", null); } catch { }
        }
    }

    // ------------------------------------------------------------------ button
    public class SsfButton : Control
    {
        public enum Kind { Primary, Secondary, Ghost, Danger }
        private Kind kind = Kind.Secondary;
        private bool hot, down;
        public int Radius = 7;
        public string Glyph = "";

        public Kind Variant { get { return kind; } set { kind = value; Invalidate(); } }

        public SsfButton()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Font = Pal.FUIB;
            Cursor = Cursors.Hand;
            Size = new Size(112, 34);
            TabStop = false;
        }
        protected override void OnMouseEnter(EventArgs e) { hot = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hot = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { down = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Pal.Bg))
                g.FillRectangle(b, ClientRectangle);

            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            Color bg, fg, br = Color.Empty;

            bool washed = false;
            if (kind == Kind.Primary)
            {
                washed = Enabled;
                bg = Pal.Accent;
                fg = Color.White;
            }
            else if (kind == Kind.Danger)
            {
                bg = down ? Color.FromArgb(96, 38, 38) : (hot ? Color.FromArgb(58, 30, 34) : Pal.Surface);
                fg = Pal.Err; br = Color.FromArgb(88, 48, 52);
            }
            else if (kind == Kind.Ghost)
            {
                bg = down ? Pal.Surface : (hot ? Pal.Elevated : Color.Transparent);
                fg = hot ? Pal.Text : Pal.Dim;
            }
            else
            {
                bg = down ? Pal.Surface : (hot ? Pal.Elevated : Color.FromArgb(22, 32, 45));
                fg = Pal.Text; br = hot ? Pal.Border : Pal.BorderSoft;
            }

            if (!Enabled)
            {
                washed = false;
                bg = (kind == Kind.Primary) ? Color.FromArgb(28, 45, 62) : Color.FromArgb(17, 25, 35);
                fg = Color.FromArgb(98, 116, 134);
                br = Pal.BorderSoft;
            }

            if (washed)
            {
                // glow ring, fuchsia -> violet wash, grain, then a top sheen
                if (hot && !down)
                {
                    for (int i = 5; i >= 1; i--)
                    {
                        Rectangle gr = new Rectangle(r.X - i, r.Y - i, r.Width + i * 2, r.Height + i * 2);
                        Gfx.Stroke(g, gr, Radius + i, Color.FromArgb(8 + (6 - i) * 6, Pal.Accent), 1.8f);
                    }
                }
                using (GraphicsPath p = Gfx.Round(r, Radius))
                using (LinearGradientBrush lb = new LinearGradientBrush(
                    new Rectangle(r.X, r.Y, Math.Max(2, r.Width), Math.Max(2, r.Height)),
                    down ? Color.FromArgb(16, 78, 128) : Pal.AccentDeep,
                    down ? Pal.AccentDeep : (hot ? Pal.AccentHot : Pal.Accent), 22f))
                {
                    g.FillPath(lb, p);
                    Grain.Apply(g, p, false);
                    Region save = g.Clip;
                    g.SetClip(p, CombineMode.Intersect);
                    using (LinearGradientBrush sheen = new LinearGradientBrush(
                        new Rectangle(r.X, r.Y, Math.Max(2, r.Width), Math.Max(2, r.Height / 2)),
                        Color.FromArgb(34, 255, 255, 255), Color.FromArgb(0, 255, 255, 255),
                        LinearGradientMode.Vertical))
                        g.FillRectangle(sheen, r.X, r.Y, r.Width, r.Height / 2);
                    g.Clip = save;
                }
            }
            else
            {
                if (bg != Color.Transparent) Gfx.Fill(g, r, Radius, bg);
                if (br != Color.Empty) Gfx.Stroke(g, r, Radius, br, 1f);
            }

            if (Glyph.Length > 0)
            {
                Size ts = TextRenderer.MeasureText(g, Text, Font);
                Size gs = TextRenderer.MeasureText(g, Glyph, Pal.FGlyph);
                int total = gs.Width + 7 + ts.Width;
                int x = (Width - total) / 2;
                TextRenderer.DrawText(g, Glyph, Pal.FGlyph,
                    new Rectangle(x, 0, gs.Width, Height), fg,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding);
                TextRenderer.DrawText(g, Text, Font,
                    new Rectangle(x + gs.Width + 7, 0, ts.Width, Height), fg,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding);
            }
            else
            {
                TextRenderer.DrawText(g, Text, Font, ClientRectangle, fg,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            }
        }
    }

    // ---------------------------------------------------------------- checkbox
    public class SsfCheck : Control
    {
        private bool chk, hot;
        public event EventHandler CheckedChanged;
        public bool Checked
        {
            get { return chk; }
            set { if (chk != value) { chk = value; Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); } }
        }
        public SsfCheck()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Font = Pal.FUI;
            Cursor = Cursors.Hand;
            Height = 26;
            TabStop = false;
        }
        protected override void OnTextChanged(EventArgs e)
        {
            Width = 26 + TextRenderer.MeasureText(Text, Font).Width + 4;
            base.OnTextChanged(e);
        }
        protected override void OnMouseEnter(EventArgs e) { hot = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hot = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnClick(EventArgs e) { if (Enabled) Checked = !Checked; base.OnClick(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Pal.Bg))
                g.FillRectangle(b, ClientRectangle);

            Rectangle box = new Rectangle(0, (Height - 18) / 2, 18, 18);
            Color acc = Enabled ? Pal.Accent : Color.FromArgb(60, 72, 88);
            if (chk)
            {
                Gfx.Fill(g, box, 5, acc);
                Gfx.Check(g, box, Enabled ? Pal.AccentDark : Color.FromArgb(30, 36, 44));
            }
            else
            {
                Gfx.Fill(g, box, 5, Pal.Field);
                Gfx.Stroke(g, box, 5, hot && Enabled ? Pal.Accent : Pal.Border, 1.4f);
            }
            TextRenderer.DrawText(g, Text, Font,
                new Rectangle(26, 0, Width - 26, Height),
                Enabled ? Pal.Text : Color.FromArgb(92, 102, 116),
                TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding);
        }
    }

    // ------------------------------------------------------------- search field
    public class SsfSearch : Control
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);

        public TextBox Box = new TextBox();
        public string Placeholder = "Search games";
        private bool hotClear;
        public event EventHandler QueryChanged;

        public string Query { get { return Box.Text; } set { Box.Text = value; } }

        public SsfSearch()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Pal.Field;
            Height = 34;
            Box.BorderStyle = BorderStyle.None;
            Box.BackColor = Pal.Field;
            Box.ForeColor = Pal.Text;
            Box.Font = Pal.FUI;
            Box.TextChanged += delegate { Invalidate(); if (QueryChanged != null) QueryChanged(this, EventArgs.Empty); };
            Box.HandleCreated += delegate { SendMessage(Box.Handle, 0x1501, (IntPtr)1, Placeholder); };
            Box.GotFocus += delegate { Invalidate(); };
            Box.LostFocus += delegate { Invalidate(); };
            Controls.Add(Box);
        }
        protected override void OnResize(EventArgs e)
        {
            Box.SetBounds(34, (Height - Box.PreferredHeight + 2) / 2, Math.Max(10, Width - 34 - 30), Box.PreferredHeight);
            base.OnResize(e);
        }
        private Rectangle ClearRect() { return new Rectangle(Width - 28, (Height - 20) / 2, 20, 20); }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            bool h = Box.Text.Length > 0 && ClearRect().Contains(e.Location);
            if (h != hotClear) { hotClear = h; Cursor = h ? Cursors.Hand : Cursors.IBeam; Invalidate(); }
            base.OnMouseMove(e);
        }
        protected override void OnMouseLeave(EventArgs e) { hotClear = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (Box.Text.Length > 0 && ClearRect().Contains(e.Location)) Box.Text = "";
            Box.Focus();
            base.OnMouseDown(e);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Pal.Bg))
                g.FillRectangle(b, ClientRectangle);

            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            Gfx.Fill(g, r, Height / 2, Pal.Field);
            Gfx.Stroke(g, r, Height / 2, Box.Focused ? Pal.Accent : Pal.Border, 1f);

            Color ico = Box.Focused ? Pal.Accent : Pal.Faint;
            using (Pen p = new Pen(ico, 1.6f))
            {
                int cx = 16, cy = Height / 2 - 1;
                g.DrawEllipse(p, cx - 5, cy - 5, 10, 10);
                g.DrawLine(p, cx + 4, cy + 4, cx + 8, cy + 8);
            }
            if (Box.Text.Length > 0)
            {
                Rectangle c = ClearRect();
                if (hotClear) Gfx.Fill(g, c, c.Width / 2, Pal.Elevated);
                using (Pen p = new Pen(hotClear ? Pal.Text : Pal.Faint, 1.5f))
                {
                    int m = 6;
                    g.DrawLine(p, c.X + m, c.Y + m, c.Right - m, c.Bottom - m);
                    g.DrawLine(p, c.Right - m, c.Y + m, c.X + m, c.Bottom - m);
                }
            }
        }
    }

    // --------------------------------------------------------- segmented switch
    public class SsfSegment : Control
    {
        private string[] items = new string[0];
        private int index = 0, hot = -1;
        public event EventHandler SelectedIndexChanged;

        public string[] Items { get { return items; } set { items = value; Invalidate(); } }
        public int SelectedIndex
        {
            get { return index; }
            set
            {
                if (index != value && value >= 0 && value < items.Length)
                {
                    index = value; Invalidate();
                    if (SelectedIndexChanged != null) SelectedIndexChanged(this, EventArgs.Empty);
                }
            }
        }
        public string SelectedItem { get { return (index >= 0 && index < items.Length) ? items[index] : ""; } }

        public SsfSegment()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Font = Pal.FUIB;
            Cursor = Cursors.Hand;
            Height = 30;
            TabStop = false;
        }
        private int HitAt(int x)
        {
            if (items.Length == 0) return -1;
            int w = Width / items.Length;
            int i = w > 0 ? x / w : 0;
            return i < 0 ? 0 : (i >= items.Length ? items.Length - 1 : i);
        }
        protected override void OnMouseMove(MouseEventArgs e) { int h = HitAt(e.X); if (h != hot) { hot = h; Invalidate(); } base.OnMouseMove(e); }
        protected override void OnMouseLeave(EventArgs e) { hot = -1; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { if (Enabled) SelectedIndex = HitAt(e.X); base.OnMouseDown(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Pal.Bg))
                g.FillRectangle(b, ClientRectangle);

            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            Gfx.Fill(g, r, Height / 2, Pal.Field);
            Gfx.Stroke(g, r, Height / 2, Pal.BorderSoft, 1f);
            if (items.Length == 0) return;

            int w = Width / items.Length;
            for (int i = 0; i < items.Length; i++)
            {
                Rectangle seg = new Rectangle(i * w, 0, w, Height);
                Color fg;
                if (i == index)
                {
                    Rectangle f = new Rectangle(seg.X + 3, 3, seg.Width - 6, Height - 6);
                    Gfx.Fill(g, f, f.Height / 2, Enabled ? Gfx.Mix(Pal.Accent, Pal.Field, 46) : Pal.Elevated);
                    Gfx.Stroke(g, f, f.Height / 2, Enabled ? Gfx.Mix(Pal.Accent, Pal.Field, 110) : Pal.Border, 1f);
                    fg = Enabled ? Pal.Accent : Pal.Faint;
                }
                else fg = (!Enabled) ? Color.FromArgb(88, 98, 112) : (i == hot ? Pal.Text : Pal.Dim);

                TextRenderer.DrawText(g, items[i], Font, seg, fg,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            }
        }
    }

    // ------------------------------------------------------------- progress bar
    public class SsfProgress : Control
    {
        private int val, max = 100;
        private bool marquee;
        private int phase;
        private Timer anim;

        public int Maximum { get { return max; } set { max = value < 1 ? 1 : value; Invalidate(); } }
        public int Value { get { return val; } set { int v = value < 0 ? 0 : (value > max ? max : value); if (v != val) { val = v; Invalidate(); } } }
        public bool Marquee
        {
            get { return marquee; }
            set { marquee = value; if (value) anim.Start(); else anim.Stop(); Invalidate(); }
        }
        public SsfProgress()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Height = 8;
            anim = new Timer();
            anim.Interval = 28;
            anim.Tick += delegate { phase = (phase + 7) % 1000; Invalidate(); };
        }
        protected override void Dispose(bool d) { if (d && anim != null) { anim.Stop(); anim.Dispose(); } base.Dispose(d); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Pal.Bg))
                g.FillRectangle(b, ClientRectangle);

            if (!marquee && val <= 0) return;

            int h = 6;
            Rectangle track = new Rectangle(0, (Height - h) / 2, Math.Max(2, Width), h);
            Gfx.Fill(g, track, h / 2, Pal.Field);

            Rectangle fill;
            if (marquee)
            {
                int w = Math.Max(70, Width / 4);
                int x = (int)((phase / 1000.0) * (Width + w)) - w;
                int left = Math.Max(0, x);
                int right = Math.Min(Width, x + w);
                fill = new Rectangle(left, track.Y, Math.Max(0, right - left), h);
            }
            else
            {
                fill = new Rectangle(0, track.Y, (int)(Width * (val / (double)max)), h);
            }
            if (fill.Width > 2)
            {
                using (GraphicsPath p = Gfx.Round(fill, h / 2))
                using (LinearGradientBrush lb = new LinearGradientBrush(
                    new Rectangle(fill.X, fill.Y, Math.Max(2, fill.Width), fill.Height),
                    Pal.AccentDeep, Pal.Accent, LinearGradientMode.Horizontal))
                {
                    g.FillPath(lb, p);
                    Grain.Apply(g, p, true);
                }
            }
        }
    }

    // ------------------------------------------------------------- rounded card
    public class SsfCard : Panel
    {
        public int Radius = 10;
        public Color Line = Pal.BorderSoft;
        public bool Outline = true;
        public bool Textured = false;
        public SsfCard()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Pal.Surface;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Pal.Bg))
                g.FillRectangle(b, ClientRectangle);
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            Gfx.Fill(g, r, Radius, BackColor);
            if (Textured) Grain.Apply(g, r, Radius, true);
            if (Outline) Gfx.Stroke(g, r, Radius, Line, 1f);
            base.OnPaint(e);
        }
    }

    // ------------------------------------------------------------- dark menus
    public class DarkColors : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground { get { return Pal.Elevated; } }
        public override Color ImageMarginGradientBegin { get { return Pal.Elevated; } }
        public override Color ImageMarginGradientMiddle { get { return Pal.Elevated; } }
        public override Color ImageMarginGradientEnd { get { return Pal.Elevated; } }
        public override Color MenuItemSelected { get { return Pal.RowSel; } }
        public override Color MenuItemSelectedGradientBegin { get { return Pal.RowSel; } }
        public override Color MenuItemSelectedGradientEnd { get { return Pal.RowSel; } }
        public override Color MenuItemBorder { get { return Pal.RowSel; } }
        public override Color MenuBorder { get { return Pal.Border; } }
        public override Color SeparatorDark { get { return Pal.Border; } }
        public override Color SeparatorLight { get { return Pal.Border; } }
    }
    public class DarkMenu : ToolStripProfessionalRenderer
    {
        public DarkMenu() : base(new DarkColors()) { }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = e.Item.Enabled ? Pal.Text : Pal.Faint;
            base.OnRenderItemText(e);
        }
    }

    // ------------------------------------------------------------- header strip
    public class SsfHeader : Panel
    {
        public SsfHeader()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Pal.Bg;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            using (LinearGradientBrush b = new LinearGradientBrush(
                new Rectangle(0, 0, Math.Max(2, Width), Math.Max(2, Height)),
                Color.FromArgb(19, 33, 50), Pal.Bg, LinearGradientMode.Horizontal))
                g.FillRectangle(b, ClientRectangle);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            // two soft light pools: fuchsia over the logo, violet trailing right
            using (GraphicsPath gp = new GraphicsPath())
            {
                gp.AddEllipse(-130, -180, 440, 320);
                using (PathGradientBrush pg = new PathGradientBrush(gp))
                {
                    pg.CenterColor = Color.FromArgb(60, Pal.Accent);
                    pg.SurroundColors = new Color[] { Color.FromArgb(0, Pal.Accent) };
                    g.FillPath(pg, gp);
                }
            }
            using (GraphicsPath gp = new GraphicsPath())
            {
                gp.AddEllipse(Width - 560, -200, 600, 340);
                using (PathGradientBrush pg = new PathGradientBrush(gp))
                {
                    pg.CenterColor = Color.FromArgb(34, Pal.Accent2);
                    pg.SurroundColors = new Color[] { Color.FromArgb(0, Pal.Accent2) };
                    g.FillPath(pg, gp);
                }
            }
            g.FillRectangle(Grain.Soft, ClientRectangle);
            using (LinearGradientBrush lb = new LinearGradientBrush(
                new Rectangle(0, Height - 2, Math.Max(2, Width), 2),
                Color.FromArgb(165, Pal.Accent), Color.FromArgb(0, Pal.Accent2), LinearGradientMode.Horizontal))
                g.FillRectangle(lb, 0, Height - 1, Width, 1);
            base.OnPaint(e);
        }
    }

    // -------------------------------------------------------------------- list
    public class GameRow
    {
        public string AppId = "";
        public string Name = "";
        public bool Checked;
        public bool NeedsFix;
        public string DesktopState = "missing";
        public string StartMenuState = "missing";
        public string IconState = "none";
        public Image Thumb;
        public object Tag;
    }

    public class SsfGameList : Control
    {
        public List<GameRow> All = new List<GameRow>();
        private List<GameRow> view = new List<GameRow>();
        private Dictionary<string, GameRow> byId = new Dictionary<string, GameRow>();

        public int RowHeight = 60;
        public int HeaderHeight = 34;
        public string EmptyText = "No games yet";
        public string EmptyHint = "";

        private int scroll, hover = -1, sel = -1;
        private bool hotCheck, hotHeadCheck, dragSb;
        private int dragDy;
        private string query = "";
        private bool brokenOnly;
        private int updating;

        public event EventHandler CheckedChanged;
        public event EventHandler SelectionChanged;
        public event EventHandler ItemActivate;

        private const int SbW = 12;

        public SsfGameList()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.Selectable, true);
            BackColor = Pal.Surface;
            TabStop = true;
        }

        // ---- data
        public void BeginUpdate() { updating++; }
        public void EndUpdate() { updating--; if (updating <= 0) { updating = 0; Refilter(); } }
        public void ClearRows()
        {
            All.Clear(); view.Clear(); byId.Clear();
            scroll = 0; sel = -1; hover = -1;
            Invalidate();
        }
        public void AddRow(GameRow r)
        {
            All.Add(r);
            byId[r.AppId] = r;
            if (updating == 0) Refilter();
        }
        public GameRow Find(string appId)
        {
            GameRow r; if (byId.TryGetValue(appId, out r)) return r; return null;
        }
        public void SetFilter(string q, bool onlyBroken)
        {
            query = (q == null) ? "" : q.Trim();
            brokenOnly = onlyBroken;
            Refilter();
        }
        private bool Match(GameRow r)
        {
            if (brokenOnly && !r.NeedsFix) return false;
            if (query.Length == 0) return true;
            return r.Name.IndexOf(query, StringComparison.OrdinalIgnoreCase) >= 0 ||
                   r.AppId.IndexOf(query, StringComparison.OrdinalIgnoreCase) >= 0;
        }
        public void Refilter()
        {
            if (updating > 0) return;
            GameRow keep = (sel >= 0 && sel < view.Count) ? view[sel] : null;
            view.Clear();
            for (int i = 0; i < All.Count; i++) if (Match(All[i])) view.Add(All[i]);
            sel = (keep != null) ? view.IndexOf(keep) : -1;
            ClampScroll();
            Invalidate();
        }
        public int TotalCount { get { return All.Count; } }
        public int VisibleCount { get { return view.Count; } }
        public int CheckedCount { get { int n = 0; for (int i = 0; i < All.Count; i++) if (All[i].Checked) n++; return n; } }
        public int NeedsFixCount { get { int n = 0; for (int i = 0; i < All.Count; i++) if (All[i].NeedsFix) n++; return n; } }
        public string[] CheckedIds
        {
            get
            {
                List<string> l = new List<string>();
                for (int i = 0; i < All.Count; i++) if (All[i].Checked) l.Add(All[i].AppId);
                return l.ToArray();
            }
        }
        public GameRow SelectedRow { get { return (sel >= 0 && sel < view.Count) ? view[sel] : null; } }

        public void SetAllChecked(bool v)
        {
            for (int i = 0; i < All.Count; i++) All[i].Checked = v;
            Invalidate(); Fire();
        }
        public void SetVisibleChecked(bool v)
        {
            for (int i = 0; i < view.Count; i++) view[i].Checked = v;
            Invalidate(); Fire();
        }
        public void CheckNeedsFix()
        {
            for (int i = 0; i < All.Count; i++) All[i].Checked = All[i].NeedsFix;
            Invalidate(); Fire();
        }
        private void Fire() { if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); }
        public void RowChanged(GameRow r) { Invalidate(); }

        // ---- geometry
        private int Viewport { get { return Math.Max(0, Height - HeaderHeight); } }
        private int Content { get { return view.Count * RowHeight; } }
        private bool NeedSb { get { return Content > Viewport; } }
        private void ClampScroll()
        {
            int maxs = Math.Max(0, Content - Viewport);
            if (scroll > maxs) scroll = maxs;
            if (scroll < 0) scroll = 0;
        }
        private int ListW { get { return Width - (NeedSb ? SbW : 0); } }
        private Rectangle ColIcon  { get { int w = 118; return new Rectangle(ListW - 14 - w, 0, w, 0); } }
        private Rectangle ColStart { get { int w = 112; return new Rectangle(ColIcon.X - w, 0, w, 0); } }
        private Rectangle ColDesk  { get { int w = 100; return new Rectangle(ColStart.X - w, 0, w, 0); } }
        private Rectangle CheckBox(int y) { return new Rectangle(18, y + (RowHeight - 18) / 2, 18, 18); }
        private Rectangle HeadBox() { return new Rectangle(18, (HeaderHeight - 18) / 2, 18, 18); }
        private Rectangle ThumbBox(int y) { return new Rectangle(48, y + (RowHeight - 40) / 2, 40, 40); }

        private int IndexAt(int y)
        {
            if (y < HeaderHeight) return -1;
            int i = (y - HeaderHeight + scroll) / RowHeight;
            return (i >= 0 && i < view.Count) ? i : -1;
        }
        private Rectangle ThumbRect()
        {
            int vp = Viewport;
            if (!NeedSb || vp <= 0) return Rectangle.Empty;
            int th = Math.Max(38, (int)(vp * (vp / (double)Content)));
            int maxs = Math.Max(1, Content - vp);
            int ty = HeaderHeight + (int)((vp - th) * (scroll / (double)maxs));
            return new Rectangle(Width - SbW + 3, ty, 6, th);
        }

        // ---- input
        protected override bool IsInputKey(Keys k)
        {
            if (k == Keys.Up || k == Keys.Down || k == Keys.Space || k == Keys.Home || k == Keys.End ||
                k == Keys.PageUp || k == Keys.PageDown) return true;
            return base.IsInputKey(k);
        }
        protected override void OnMouseWheel(MouseEventArgs e)
        {
            scroll -= (e.Delta / 120) * RowHeight;
            ClampScroll(); Invalidate();
            base.OnMouseWheel(e);
        }
        protected override void OnMouseLeave(EventArgs e)
        {
            hover = -1; hotCheck = false; hotHeadCheck = false; Invalidate(); base.OnMouseLeave(e);
        }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            if (dragSb)
            {
                Rectangle t = ThumbRect();
                int travel = Math.Max(1, Viewport - t.Height);
                int y = e.Y - dragDy - HeaderHeight;
                scroll = (int)((y / (double)travel) * Math.Max(0, Content - Viewport));
                ClampScroll(); Invalidate(); return;
            }
            int i = IndexAt(e.Y);
            bool hc = false, hh = false;
            if (e.Y < HeaderHeight) hh = HeadBox().Contains(e.Location);
            if (i >= 0) hc = CheckBox(HeaderHeight + i * RowHeight - scroll).Contains(e.Location);
            if (i != hover || hc != hotCheck || hh != hotHeadCheck)
            {
                hover = i; hotCheck = hc; hotHeadCheck = hh;
                Cursor = (hc || hh) ? Cursors.Hand : Cursors.Default;
                Invalidate();
            }
            base.OnMouseMove(e);
        }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            Focus();
            if (NeedSb && e.X >= Width - SbW)
            {
                Rectangle t = ThumbRect();
                if (t.Contains(e.Location)) { dragSb = true; dragDy = e.Y - t.Y; }
                else { scroll += (e.Y < t.Y ? -1 : 1) * Viewport; ClampScroll(); Invalidate(); }
                return;
            }
            if (e.Y < HeaderHeight)
            {
                if (HeadBox().Contains(e.Location))
                {
                    bool allChecked = view.Count > 0;
                    for (int i = 0; i < view.Count; i++) if (!view[i].Checked) { allChecked = false; break; }
                    SetVisibleChecked(!allChecked);
                }
                return;
            }
            int idx = IndexAt(e.Y);
            if (idx < 0) return;
            if (e.Button == MouseButtons.Left && CheckBox(HeaderHeight + idx * RowHeight - scroll).Contains(e.Location))
            {
                view[idx].Checked = !view[idx].Checked;
                Invalidate(); Fire();
                return;
            }
            if (sel != idx)
            {
                sel = idx; Invalidate();
                if (SelectionChanged != null) SelectionChanged(this, EventArgs.Empty);
            }
            base.OnMouseDown(e);
        }
        protected override void OnMouseUp(MouseEventArgs e) { dragSb = false; base.OnMouseUp(e); }
        protected override void OnMouseDoubleClick(MouseEventArgs e)
        {
            int idx = IndexAt(e.Y);
            if (idx >= 0 && e.Button == MouseButtons.Left && ItemActivate != null &&
                !CheckBox(HeaderHeight + idx * RowHeight - scroll).Contains(e.Location))
                ItemActivate(this, EventArgs.Empty);
            base.OnMouseDoubleClick(e);
        }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            int page = Math.Max(1, Viewport / RowHeight);
            if (e.KeyCode == Keys.Down) MoveSel(1);
            else if (e.KeyCode == Keys.Up) MoveSel(-1);
            else if (e.KeyCode == Keys.PageDown) MoveSel(page);
            else if (e.KeyCode == Keys.PageUp) MoveSel(-page);
            else if (e.KeyCode == Keys.Home) { sel = view.Count > 0 ? 0 : -1; EnsureVisible(); Invalidate(); }
            else if (e.KeyCode == Keys.End) { sel = view.Count - 1; EnsureVisible(); Invalidate(); }
            else if (e.KeyCode == Keys.Space && sel >= 0) { view[sel].Checked = !view[sel].Checked; Invalidate(); Fire(); }
            else if (e.KeyCode == Keys.A && e.Control) SetVisibleChecked(true);
            else if (e.KeyCode == Keys.Enter && sel >= 0 && ItemActivate != null) ItemActivate(this, EventArgs.Empty);
            base.OnKeyDown(e);
        }
        private void MoveSel(int d)
        {
            if (view.Count == 0) return;
            sel = (sel < 0) ? 0 : sel + d;
            if (sel < 0) sel = 0;
            if (sel >= view.Count) sel = view.Count - 1;
            EnsureVisible(); Invalidate();
            if (SelectionChanged != null) SelectionChanged(this, EventArgs.Empty);
        }
        public void EnsureVisible()
        {
            if (sel < 0) return;
            int top = sel * RowHeight, bottom = top + RowHeight;
            if (top < scroll) scroll = top;
            else if (bottom > scroll + Viewport) scroll = bottom - Viewport;
            ClampScroll();
        }
        public void ScrollToTop() { scroll = 0; Invalidate(); }

        // ---- paint
        private void Pill(Graphics g, Rectangle col, int y, string text, Color fg)
        {
            Size s = TextRenderer.MeasureText(g, text, Pal.FPill);
            int w = s.Width + 20, h = 22;
            Rectangle r = new Rectangle(col.X + (col.Width - w) / 2, y + (RowHeight - h) / 2, w, h);
            Gfx.Fill(g, r, h / 2, Gfx.Mix(fg, Pal.Surface, 32));
            Gfx.Stroke(g, r, h / 2, Gfx.Mix(fg, Pal.Surface, 78), 1f);
            TextRenderer.DrawText(g, text, Pal.FPill, r, fg,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
        private void StateP(Graphics g, Rectangle col, int y, string state)
        {
            if (state == "ok") Pill(g, col, y, "Linked", Pal.Ok);
            else Pill(g, col, y, "Missing", Pal.Err);
        }
        private void IconP(Graphics g, Rectangle col, int y, string state)
        {
            if (state == "ok") Pill(g, col, y, "Real .ico", Pal.Ok);
            else if (state == "fallback") Pill(g, col, y, "steam.exe", Pal.Warn);
            else if (state == "broken") Pill(g, col, y, "Broken", Pal.Err);
            else Pill(g, col, y, "None", Pal.Faint);
        }
        private void DrawCheck(Graphics g, Rectangle box, bool on, bool hot, bool partial)
        {
            if (on)
            {
                Gfx.Fill(g, box, 5, Pal.Accent);
                Gfx.Check(g, box, Pal.AccentDark);
            }
            else if (partial)
            {
                Gfx.Fill(g, box, 5, Pal.Field);
                Gfx.Stroke(g, box, 5, Pal.Accent, 1.4f);
                using (SolidBrush b = new SolidBrush(Pal.Accent))
                    g.FillRectangle(b, box.X + 4, box.Y + 8, box.Width - 8, 3);
            }
            else
            {
                Gfx.Fill(g, box, 5, Pal.Field);
                Gfx.Stroke(g, box, 5, hot ? Pal.Accent : Pal.Border, 1.4f);
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            using (SolidBrush b = new SolidBrush(BackColor)) g.FillRectangle(b, ClientRectangle);

            Rectangle ci = ColIcon, cs = ColStart, cd = ColDesk;
            int nameX = 100;
            int nameW = Math.Max(60, cd.X - 16 - nameX);

            Region old = g.Clip;
            g.SetClip(new Rectangle(0, HeaderHeight, ListW, Math.Max(0, Height - HeaderHeight)));
            int first = Math.Max(0, scroll / RowHeight);
            int last = Math.Min(view.Count - 1, (scroll + Viewport) / RowHeight);
            for (int i = first; i <= last; i++)
            {
                GameRow r = view[i];
                int y = HeaderHeight + i * RowHeight - scroll;
                Rectangle rr = new Rectangle(0, y, ListW, RowHeight);

                if (i == sel)
                {
                    using (LinearGradientBrush b = new LinearGradientBrush(
                        new Rectangle(rr.X, rr.Y, Math.Max(2, rr.Width), rr.Height),
                        Pal.RowSel, Pal.Surface, LinearGradientMode.Horizontal))
                        g.FillRectangle(b, rr);
                    using (LinearGradientBrush b = new LinearGradientBrush(
                        new Rectangle(0, y, 4, RowHeight), Pal.Accent, Pal.AccentDeep,
                        LinearGradientMode.Vertical))
                        g.FillRectangle(b, 0, y, 3, RowHeight);
                }
                else if (i == hover)
                {
                    using (SolidBrush b = new SolidBrush(Pal.RowHover)) g.FillRectangle(b, rr);
                }
                using (Pen p = new Pen(Pal.RowLine))
                    g.DrawLine(p, 14, rr.Bottom - 1, ListW - 14, rr.Bottom - 1);

                DrawCheck(g, CheckBox(y), r.Checked, hotCheck && i == hover, false);

                Rectangle tb = ThumbBox(y);
                using (GraphicsPath p = Gfx.Round(tb, 9))
                {
                    Region save = g.Clip;
                    g.SetClip(p, CombineMode.Intersect);
                    if (r.Thumb != null) g.DrawImage(r.Thumb, tb);
                    else using (SolidBrush b = new SolidBrush(Pal.Elevated)) g.FillRectangle(b, tb);
                    g.Clip = save;
                }
                Gfx.Stroke(g, tb, 9, Color.FromArgb(64, 255, 255, 255), 1f);

                TextRenderer.DrawText(g, r.Name, Pal.FRow,
                    new Rectangle(nameX, y + 11, nameW, 20),
                    (i == sel) ? Color.White : Pal.Text,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);

                string sub = "AppID " + r.AppId + (r.NeedsFix ? "   •   needs fixing" : "   •   up to date");
                TextRenderer.DrawText(g, sub, Pal.FSmall,
                    new Rectangle(nameX, y + 30, nameW, 18),
                    r.NeedsFix ? Pal.Dim : Pal.Faint,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);

                StateP(g, cd, y, r.DesktopState);
                StateP(g, cs, y, r.StartMenuState);
                IconP(g, ci, y, r.IconState);
            }
            g.Clip = old;

            if (view.Count == 0)
            {
                Rectangle box = new Rectangle(0, HeaderHeight, ListW, Math.Max(0, Height - HeaderHeight));
                TextRenderer.DrawText(g, EmptyText, Pal.FRow,
                    new Rectangle(box.X, box.Y + box.Height / 2 - 26, box.Width, 24), Pal.Dim,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                if (EmptyHint.Length > 0)
                    TextRenderer.DrawText(g, EmptyHint, Pal.FUI,
                        new Rectangle(box.X, box.Y + box.Height / 2, box.Width, 22), Pal.Faint,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            }

            Rectangle hd = new Rectangle(0, 0, Width, HeaderHeight);
            using (LinearGradientBrush b = new LinearGradientBrush(
                new Rectangle(0, 0, Math.Max(2, Width), HeaderHeight),
                Pal.Elevated, Color.FromArgb(21, 31, 44), LinearGradientMode.Vertical))
                g.FillRectangle(b, hd);
            g.FillRectangle(Grain.Soft, hd);
            using (LinearGradientBrush b = new LinearGradientBrush(
                new Rectangle(0, HeaderHeight - 2, Math.Max(2, Width), 2),
                Color.FromArgb(120, Pal.Accent), Color.FromArgb(30, Pal.Accent2), LinearGradientMode.Horizontal))
                g.FillRectangle(b, 0, HeaderHeight - 1, Width, 1);

            bool allC = view.Count > 0, anyC = false;
            for (int i = 0; i < view.Count; i++) { if (view[i].Checked) anyC = true; else allC = false; }
            DrawCheck(g, HeadBox(), allC, hotHeadCheck, anyC && !allC);

            TextRenderer.DrawText(g, "GAME", Pal.FHead, new Rectangle(nameX, 0, nameW, HeaderHeight), Pal.Faint,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, "DESKTOP", Pal.FHead, new Rectangle(cd.X, 0, cd.Width, HeaderHeight), Pal.Faint,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            TextRenderer.DrawText(g, "START MENU", Pal.FHead, new Rectangle(cs.X, 0, cs.Width, HeaderHeight), Pal.Faint,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            TextRenderer.DrawText(g, "ICON", Pal.FHead, new Rectangle(ci.X, 0, ci.Width, HeaderHeight), Pal.Faint,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);

            if (NeedSb)
            {
                Rectangle t = ThumbRect();
                Gfx.Fill(g, t, 3, dragSb ? Pal.Accent : Color.FromArgb(58, 72, 90));
            }
        }
    }
}
'@

[SSF.Chrome]::DarkApp()

# PowerShell-side view of the palette (single source of truth lives in C#)
$theme = @{
    Window  = [SSF.Pal]::Bg
    Surface = [SSF.Pal]::Surface
    Field   = [SSF.Pal]::Field
    Border  = [SSF.Pal]::Border
    Text    = [SSF.Pal]::Text
    Dim     = [SSF.Pal]::Dim
    Faint   = [SSF.Pal]::Faint
    Accent  = [SSF.Pal]::Accent
    Ok      = [SSF.Pal]::Ok
    Warn    = [SSF.Pal]::Warn
    Err     = [SSF.Pal]::Err
}

# =============================================================================
#  Shared state (UI thread <-> background runspace)
# =============================================================================
$sync = [hashtable]::Synchronized(@{
    Phase            = 'idle'      # idle | scanning | applying | cancelling | done
    CancelRequested  = $false
    Done             = $true
    LogQueue         = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    GameQueue        = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    ResultQueue      = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    IconUpdates      = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    ProgressMax      = 0
    ProgressValue    = 0
    ProgressCurrent  = ''
    Games            = @()
    InstalledIds     = @()
    SteamPath        = ''
    SteamExe         = ''
    GamesDir         = ''
    LibraryCacheDir  = ''
    DesktopDir       = ''
    StartMenuDir     = ''
    DestDesktop      = $true
    DestStartMenu    = $true
    RemoveOrphans    = $true
    CdnBase          = ''
    CdnName          = ''
    SelectedAppIds   = @()
    Summary          = $null
    Error            = $null
})

function Write-Log {
    param([string]$Level, [string]$Text)
    $sync.LogQueue.Enqueue(@{ L = $Level; T = (Get-Date -Format 'HH:mm:ss') + '  ' + $Text })
}

# =============================================================================
#  Core logic (ported from the console edition v1.1)
# =============================================================================

function Find-SteamInstall {
    foreach ($r in @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam","HKCU:\SOFTWARE\Valve\Steam")) {
        $p = (Get-ItemProperty $r -Name "InstallPath" -EA SilentlyContinue).InstallPath
        if ($p -and (Test-Path (Join-Path $p "steam.exe"))) { return $p }
    }
    return $null
}

function Get-SteamLibraries {
    param([string]$SteamPath)
    $libs = @($SteamPath)
    $vdfPath = Join-Path $SteamPath "steamapps\libraryfolders.vdf"
    if (-not (Test-Path $vdfPath)) { return $libs }
    $content = [System.IO.File]::ReadAllText($vdfPath, [System.Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
        $p = $m.Groups[1].Value -replace '\\\\', '\'
        if ($p -ne $SteamPath -and (Test-Path $p)) { $libs += $p }
    }
    return $libs | Select-Object -Unique
}

function Get-InstalledGames {
    param([string[]]$Libraries)
    $games = @()
    foreach ($lib in $Libraries) {
        $sa = Join-Path $lib "steamapps"
        if (-not (Test-Path $sa)) { continue }
        Get-ChildItem $sa -Filter "appmanifest_*.acf" -EA SilentlyContinue | ForEach-Object {
            $c = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
            if (-not $c) { return }
            $appId = if ($c -match '"appid"\s+"(\d+)"') { $matches[1] } else { $null }
            $name = if ($c -match '"name"\s+"([^"]+)"') { $matches[1] } else { $null }
            $dir = if ($c -match '"installdir"\s+"([^"]+)"') { $matches[1] } else { $null }
            if ($appId -and $name -and $dir -and $name -ne "Steamworks Common Redistributables") {
                $gamePath = Join-Path (Join-Path $lib "steamapps\common") $dir
                if (Test-Path $gamePath) { $games += @{ AppId = $appId; Name = $name } }
            }
        }
    }
    return $games
}

function Read-UrlShortcut {
    param([string]$Path)
    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::ASCII)
    $url = ""; $iconFile = ""
    if ($content -match 'URL=(steam://rungameid/(\d+))') { $url = $matches[1] }
    if ($content -match 'IconFile=(.+?)[\r\n]') { $iconFile = $matches[1].Trim() }
    $appId = if ($url -match '(\d+)$') { $matches[1] } else { $null }
    $usesFallback = ($iconFile -match 'steam\.exe$')
    $iconMissing = ($iconFile -and -not (Test-Path $iconFile))
    return @{ AppId = $appId; IconFile = $iconFile; IconMissing = $iconMissing; NeedsRealIcon = ($iconMissing -or $usesFallback -or -not $iconFile) }
}

function Find-SteamShortcuts {
    param([string[]]$Paths)
    $shortcuts = @()
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        Get-ChildItem $p -Filter "*.url" -EA SilentlyContinue | ForEach-Object {
            $info = Read-UrlShortcut $_.FullName
            if ($info.AppId) {
                $shortcuts += @{
                    AppId = $info.AppId; Path = $_.FullName
                    IconFile = $info.IconFile; IconMissing = $info.IconMissing; NeedsRealIcon = $info.NeedsRealIcon; Dir = $p
                }
            }
        }
    }
    return $shortcuts
}

function Get-SteamAppInfo {
    param([string]$AppId)
    $tmpFile = Join-Path $env:TEMP "steam_api_${AppId}.json"
    $null = & curl.exe -s -o $tmpFile --connect-timeout 5 --max-time 15 "https://api.steamcmd.net/v1/info/${AppId}" 2>$null
    if (-not (Test-Path $tmpFile)) { return $null }
    $json = [System.IO.File]::ReadAllText($tmpFile, [System.Text.Encoding]::UTF8)
    Remove-Item $tmpFile -Force -EA SilentlyContinue
    if (-not $json) { return $null }
    $hash = if ($json -match '"clienticon"\s*:\s*"([0-9a-f]{40})"') { $matches[1] } else { $null }
    $name = $null
    $allNames = [regex]::Matches($json, '"name"\s*:\s*"([^"]+)"')
    foreach ($m in $allNames) {
        $endPos = $m.Index + $m.Length
        $afterLen = [Math]::Min(30, $json.Length - $endPos)
        $after = $json.Substring($endPos, $afterLen)
        if ($after -match '"(osarch|name_localized)"') { $name = $m.Groups[1].Value; break }
    }
    return @{ Hash = $hash; Name = $name }
}

function Download-Icon {
    param([string]$AppId,[string]$Hash,[string]$GamesDir,[string]$CdnBase)
    $icoPath = Join-Path $GamesDir "${Hash}.ico"
    if (Test-Path $icoPath) { return $icoPath }
    $url = "${CdnBase}/${AppId}/${Hash}.ico"
    & curl.exe -s -o $icoPath --connect-timeout 5 --max-time 30 $url 2>$null | Out-Null
    if (Test-Path $icoPath) {
        if ((Get-Item $icoPath -EA SilentlyContinue).Length -gt 500) { return $icoPath }
        Remove-Item $icoPath -Force -EA SilentlyContinue
    }
    return $null
}

function Write-UrlShortcut {
    param([string]$Path,[string]$AppId,[string]$IconPath,[string]$SteamExe)
    $iconLine = if ($IconPath) { "IconFile=$IconPath" } else { "IconFile=$SteamExe" }
    $content = "[{000214A0-0000-0000-C000-000000000046}]`r`nProp3=19,2`r`n[InternetShortcut]`r`nIDList=`r`nIconIndex=0`r`nURL=steam://rungameid/${AppId}`r`n${iconLine}`r`n"
    [System.IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding $false))
}

function Sanitize-Name {
    param([string]$Name)
    $s = [regex]::Replace($Name, '\\u([0-9a-fA-F]{4})', { [char][Convert]::ToInt32($args[0].Groups[1].Value, 16) })
    $s = ($s -replace '[<>:"/\\|?*]', '').Trim()
    $s = ($s -replace '\s{2,}', ' ').Trim()
    return $s
}

# Returns the best local artwork file for a game (offline, instant), or $null.
function Get-LibraryArtwork {
    param([string]$AppId, [string]$LibraryCacheDir)
    $dir = Join-Path $LibraryCacheDir $AppId
    if (-not (Test-Path $dir)) { return $null }
    $header = Join-Path $dir "header.jpg"
    if (Test-Path -LiteralPath $header) { return $header }
    $hex = Get-ChildItem $dir -Filter "*.jpg" -EA SilentlyContinue |
        Where-Object { $_.BaseName -match '^[0-9a-f]{40}$' } |
        Select-Object -First 1
    if ($hex) { return $hex.FullName }
    return $null
}

# =============================================================================
#  Thumbnail pipeline (UI thread only)
# =============================================================================

$tilePalette = @(
    [System.Drawing.Color]::FromArgb( 30,  94, 148), [System.Drawing.Color]::FromArgb( 38, 118, 140),
    [System.Drawing.Color]::FromArgb( 46,  78, 132), [System.Drawing.Color]::FromArgb( 26, 108, 116),
    [System.Drawing.Color]::FromArgb( 58, 100, 160), [System.Drawing.Color]::FromArgb( 34,  86, 122),
    [System.Drawing.Color]::FromArgb( 70, 112, 152), [System.Drawing.Color]::FromArgb( 42, 132, 168)
)

function ConvertTo-Thumbnail {
    # Always returns a square $Size x $Size Bitmap; never throws.
    param([string]$ImagePath, [string]$Letter, [long]$TileSeed, [int]$Size = 40)
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = $null; $clone = $null
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

        if ($ImagePath -and (Test-Path -LiteralPath $ImagePath)) {
            try {
                if ([System.IO.Path]::GetExtension($ImagePath) -ieq '.ico') {
                    $ico = New-Object System.Drawing.Icon($ImagePath)
                    try { $clone = $ico.ToBitmap() } finally { $ico.Dispose() }
                } else {
                    $src = [System.Drawing.Image]::FromFile($ImagePath)
                    try { $clone = New-Object System.Drawing.Bitmap($src) } finally { $src.Dispose() }
                }
            } catch { $clone = $null }
        }

        $bg = New-Object System.Drawing.SolidBrush($theme.Surface)
        $g.FillRectangle($bg, 0, 0, $Size, $Size)
        $bg.Dispose()

        if ($clone) {
            # center-crop to square, then scale - never stretch
            $side = [Math]::Min($clone.Width, $clone.Height)
            $x = [int](($clone.Width  - $side) / 2)
            $y = [int](($clone.Height - $side) / 2)
            $srcRect  = New-Object System.Drawing.Rectangle($x, $y, $side, $side)
            $destRect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
            $g.DrawImage($clone, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        } else {
            $c = $tilePalette[[int]([Math]::Abs($TileSeed) % $tilePalette.Count)]
            $brush = New-Object System.Drawing.SolidBrush($c)
            $g.FillRectangle($brush, 0, 0, $Size, $Size)
            $brush.Dispose()
            $letter = if ($Letter -and $Letter.Length) { $Letter.Substring(0,1).ToUpperInvariant() } else { '?' }
            $fontSize = [float]([Math]::Max(10, [int]($Size * 0.5)))
            $font = New-Object System.Drawing.Font('Segoe UI', $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
            $fmt = New-Object System.Drawing.StringFormat
            $fmt.Alignment = [System.Drawing.StringAlignment]::Center
            $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
            $fg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
            $g.DrawString($letter, $font, $fg, (New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)), $fmt)
            $font.Dispose(); $fg.Dispose(); $fmt.Dispose()
        }
        return $bmp
    } finally {
        if ($g)     { $g.Dispose() }
        if ($clone) { $clone.Dispose() }
    }
}

# =============================================================================
#  Background workers (assembled into self-contained script text)
# =============================================================================

$scanBody = {
    $ErrorActionPreference = 'Continue'
    try {
        $sync.Phase = 'scanning'
        $sync.ProgressCurrent = 'Locating Steam...'
        $sync.Games = @(); $sync.InstalledIds = @()
        $sync.GameQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'

        $steam = Find-SteamInstall
        if (-not $steam) {
            Write-Log 'err' 'Steam installation not found (checked HKLM/HKCU Valve\Steam)'
            return
        }
        $sync.SteamPath       = $steam
        $sync.SteamExe        = Join-Path $steam 'steam.exe'
        $sync.GamesDir        = Join-Path $steam 'steam\games'
        $sync.LibraryCacheDir = Join-Path $steam 'appcache\librarycache'
        $sync.DesktopDir      = [Environment]::GetFolderPath('Desktop')
        $sync.StartMenuDir    = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Steam'

        $libs = @(Get-SteamLibraries $steam)
        Write-Log 'info' ("Steam: " + $steam)
        Write-Log 'info' ("Libraries: " + $libs.Count)

        $games = @(Get-InstalledGames $libs)
        $sync.Games = $games
        $sync.InstalledIds = @($games | ForEach-Object { $_.AppId })

        $desktopSc = @(Find-SteamShortcuts @($sync.DesktopDir) | Where-Object { $_.Dir -eq $sync.DesktopDir })
        $menuSc     = @(Find-SteamShortcuts @($sync.StartMenuDir) | Where-Object { $_.Dir -eq $sync.StartMenuDir })

        foreach ($game in $games) {
            $ds = $desktopSc | Where-Object { $_.AppId -eq $game.AppId } | Select-Object -First 1
            $sm = $menuSc     | Where-Object { $_.AppId -eq $game.AppId } | Select-Object -First 1

            # game-level icon state
            $any = @($ds) + @($sm) | Where-Object { $_ }
            $iconState = 'none'
            $goodIcon  = $null
            if ($any.Count) {
                $good = $any | Where-Object { $_.IconFile -and (Test-Path -LiteralPath $_.IconFile) -and $_.IconFile -notmatch 'steam\.exe$' } | Select-Object -First 1
                if ($good) { $iconState = 'ok'; $goodIcon = $good.IconFile }
                elseif (($any | Where-Object { $_.IconMissing }).Count) { $iconState = 'broken' }
                else { $iconState = 'fallback' }
            }

            # display artwork: real icon > library cache art > letter tile
            $art = $goodIcon
            if (-not $art) { $art = Get-LibraryArtwork -AppId $game.AppId -LibraryCacheDir $sync.LibraryCacheDir }

            $needsFix = ((-not $ds) -or (-not $sm) -or ($iconState -ne 'ok'))

            $vm = @{
                AppId         = $game.AppId
                Name          = $game.Name
                DesktopState  = if ($ds) { 'ok' } else { 'missing' }
                StartMenuState= if ($sm) { 'ok' } else { 'missing' }
                IconState     = $iconState
                ArtPath       = $art
                NeedsFix      = $needsFix
            }
            $sync.GameQueue.Enqueue($vm)
        }

        Write-Log 'ok' ("Found " + $games.Count + " games across " + $libs.Count + " libraries")
    } catch {
        $sync.Error = ($_ | Out-String).Trim()
        Write-Log 'err' ("Scan failed: " + $_.Exception.Message)
    } finally {
        $sync.Phase = 'done'
        $sync.Done = $true
    }
}

$applyBody = {
    $ErrorActionPreference = 'Continue'
    $summary = @{ Created = 0; Fixed = 0; OkCount = 0; Failed = 0; OrphansRemoved = 0; Cancelled = $false }
    try {
        $sync.Phase = 'applying'
        $sync.ResultQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $sync.IconUpdates = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'

        $desktop  = $sync.DesktopDir
        $menuDir  = $sync.StartMenuDir
        $steamExe = $sync.SteamExe
        $gamesDir = $sync.GamesDir
        if (-not (Test-Path $gamesDir)) { New-Item -Path $gamesDir -ItemType Directory -Force | Out-Null }
        $cdnBase = $sync.CdnBase

        # fresh scan of enabled destinations only - never trust minutes-old UI state
        $scanPaths = @()
        if ($sync.DestDesktop)   { $scanPaths += $desktop }
        if ($sync.DestStartMenu) { $scanPaths += $menuDir }
        $existing = @(Find-SteamShortcuts $scanPaths)

        $games = @($sync.Games | Where-Object { $sync.SelectedAppIds -contains $_.AppId })
        $total = $games.Count
        $sync.ProgressMax = $total
        $sync.ProgressValue = 0
        if ($sync.RemoveOrphans) { $sync.ProgressMax = $total + 1 }

        $i = 0
        foreach ($game in $games) {
            if ($sync.CancelRequested) { $summary.Cancelled = $true; Write-Log 'warn' 'Cancelled by user'; break }
            $i++
            $sync.ProgressValue = $i
            $sync.ProgressCurrent = $game.Name
            $appId = $game.AppId

            try {
                $ds = $existing | Where-Object { $_.AppId -eq $appId -and $_.Dir -eq $desktop } | Select-Object -First 1
                $sm = $existing | Where-Object { $_.AppId -eq $appId -and $_.Dir -eq $menuDir } | Select-Object -First 1

                $iconIssue = $false
                if ($sync.DestDesktop)   { if (-not $ds -or $ds.NeedsRealIcon) { $iconIssue = $true } }
                if ($sync.DestStartMenu) { if (-not $sm -or $sm.NeedsRealIcon) { $iconIssue = $true } }

                # name: authoritative API name when doing work; otherwise keep what's on disk
                $info = $null
                $name = $null
                if ($iconIssue) {
                    $info = Get-SteamAppInfo $appId
                    if ($info -and $info.Name) { $name = Sanitize-Name $info.Name }
                }
                if (-not $name) {
                    $anySc = @($ds, $sm) | Where-Object { $_ } | Select-Object -First 1
                    if ($anySc) { $name = [System.IO.Path]::GetFileNameWithoutExtension($anySc.Path) }
                    else        { $name = Sanitize-Name $game.Name }
                }

                # icon resolution
                $iconPath = $null
                $iconRes  = 'none'
                if ($iconIssue) {
                    if ($info -and $info.Hash) {
                        $iconPath = Download-Icon -AppId $appId -Hash $info.Hash -GamesDir $gamesDir -CdnBase $cdnBase
                        if ($iconPath) {
                            $iconRes = 'downloaded'
                            $sync.IconUpdates.Enqueue(@{ AppId = $appId; IconPath = $iconPath })
                        } else { $iconRes = 'fail' }
                    } else { $iconRes = 'none' }
                } else {
                    $good = @($ds, $sm) | Where-Object { $_ -and $_.IconFile -and (Test-Path -LiteralPath $_.IconFile) -and $_.IconFile -notmatch 'steam\.exe$' } | Select-Object -First 1
                    if ($good) { $iconPath = $good.IconFile; $iconRes = 'kept' }
                }

                $desktopRes = 'skip'; $menuRes = 'skip'

                foreach ($dest in @(
                    @{ Enabled = $sync.DestDesktop;   Dir = $desktop; Key = 'desktop' },
                    @{ Enabled = $sync.DestStartMenu; Dir = $menuDir; Key = 'menu' }
                )) {
                    if (-not $dest.Enabled) { continue }
                    $targetPath = Join-Path $dest.Dir ($name + '.url')
                    $stale = @($existing | Where-Object { $_.AppId -eq $appId -and $_.Dir -eq $dest.Dir -and $_.Path -ne $targetPath })
                    $hadAny = [bool]($existing | Where-Object { $_.AppId -eq $appId -and $_.Dir -eq $dest.Dir })

                    if (-not $iconIssue -and $stale.Count -eq 0 -and (Test-Path -LiteralPath $targetPath)) {
                        $res = 'ok'
                    } else {
                        foreach ($old in $stale) { Remove-Item -LiteralPath $old.Path -Force -EA SilentlyContinue }
                        if ($dest.Key -eq 'menu' -and -not (Test-Path $menuDir)) {
                            New-Item -Path $menuDir -ItemType Directory -Force | Out-Null
                        }
                        Write-UrlShortcut -Path $targetPath -AppId $appId -IconPath $iconPath -SteamExe $steamExe
                        $res = if ($hadAny) { 'fixed' } else { 'created' }
                    }
                    if ($dest.Key -eq 'desktop') { $desktopRes = $res } else { $menuRes = $res }
                    if ($res -eq 'created') { $summary.Created++ }
                    elseif ($res -eq 'fixed') { $summary.Fixed++ }
                    elseif ($res -eq 'ok') { $summary.OkCount++ }
                }

                if ($desktopRes -eq 'fail' -or $menuRes -eq 'fail' -or ($iconRes -eq 'fail' -or $iconRes -eq 'none') -and ($desktopRes -ne 'ok' -or $menuRes -ne 'ok')) {
                    $summary.Failed++
                }

                $line = '[' + $game.Name + ']  desktop: ' + $desktopRes + ', menu: ' + $menuRes + ', icon: ' + $iconRes
                $lvl = if ($iconRes -eq 'fail' -or $iconRes -eq 'none') { 'warn' } else { 'ok' }
                Write-Log $lvl $line

                $sync.ResultQueue.Enqueue(@{
                    AppId = $appId; Desktop = $desktopRes; StartMenu = $menuRes; Icon = $iconRes
                })
            } catch {
                $summary.Failed++
                Write-Log 'err' ($game.Name + ': ' + $_.Exception.Message)
                $sync.ResultQueue.Enqueue(@{
                    AppId = $appId; Desktop = 'fail'; StartMenu = 'fail'; Icon = 'fail'
                })
            }
        }

        # orphan cleanup: shortcuts pointing at games that are no longer installed
        if ($sync.RemoveOrphans -and -not $summary.Cancelled) {
            $sync.ProgressCurrent = 'Removing orphaned shortcuts...'
            $orphans = @(Find-SteamShortcuts @($desktop, $menuDir) |
                Where-Object { $sync.InstalledIds -notcontains $_.AppId })
            foreach ($orphan in $orphans) {
                Remove-Item -LiteralPath $orphan.Path -Force -EA SilentlyContinue
                $summary.OrphansRemoved++
                Write-Log 'warn' ('Removed orphan: ' + [System.IO.Path]::GetFileName($orphan.Path))
            }
            if ($orphans.Count -eq 0) { Write-Log 'info' 'No orphaned shortcuts found' }
            $sync.ProgressValue = $sync.ProgressMax
        }

        # refresh icon cache + Explorer
        & ie4uinit.exe -show 2>$null
        try {
            [void][SSF.Native]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
        } catch { }

        $sync.Summary = $summary
    } catch {
        $sync.Error = ($_ | Out-String).Trim()
        Write-Log 'err' ('Apply failed: ' + $_.Exception.Message)
    } finally {
        $sync.Phase = 'done'
        $sync.Done = $true
    }
}

# =============================================================================
#  Background work plumbing
# =============================================================================

$iconCacheBody = {
    $ErrorActionPreference = 'Continue'
    try {
        $sync.Phase = 'iconcache'
        Write-Log 'info' 'Rebuilding the Windows icon cache...'

        $ie4 = Join-Path $env:SystemRoot 'System32\ie4uinit.exe'
        if (Test-Path -LiteralPath $ie4) {
            # -show on Win10/11, -ClearIconCache on older builds. Both are harmless.
            foreach ($arg in @('-show', '-ClearIconCache')) {
                try { Start-Process $ie4 -ArgumentList $arg -Wait -WindowStyle Hidden -EA Stop } catch { }
            }
            Write-Log 'ok' '  ie4uinit.exe asked Windows to refresh its icon cache'
        }

        Write-Log 'warn' '  Closing Explorer so the cache files unlock...'
        Get-Process explorer -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep -Milliseconds 1200

        $patterns = @(
            (Join-Path $env:LOCALAPPDATA 'IconCache.db'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer\iconcache*.db')
        )
        $removed = 0; $locked = 0
        foreach ($pat in $patterns) {
            Get-ChildItem -Path $pat -Force -EA SilentlyContinue | ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Force -EA Stop; $removed++ }
                catch { $locked++; Write-Log 'dim' ('  still locked: ' + $_.Name) }
            }
        }
        Write-Log 'ok' ('  Deleted ' + $removed + ' icon cache file(s)' + $(if ($locked) { ', ' + $locked + ' locked' } else { '' }))

        if (-not (Get-Process explorer -EA SilentlyContinue)) {
            Start-Process explorer.exe
            Write-Log 'ok' '  Explorer restarted'
        }
        try { [SSF.Native]::SHChangeNotify(0x8000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero) } catch { }
        Write-Log 'ok' 'Icon cache rebuilt - Windows will redraw shortcut icons from scratch'
    } catch {
        $sync.Error = ($_ | Out-String).Trim()
        Write-Log 'err' ('Icon cache rebuild failed: ' + $_.Exception.Message)
    } finally {
        $sync.Phase = 'done'
        $sync.Done = $true
    }
}

$portableFunctions = @(
    'Find-SteamInstall','Get-SteamLibraries','Get-InstalledGames','Read-UrlShortcut',
    'Find-SteamShortcuts','Get-SteamAppInfo','Download-Icon','Write-UrlShortcut',
    'Sanitize-Name','Write-Log','Get-LibraryArtwork'
)

function Start-BackgroundWork {
    param([scriptblock]$Body)
    Stop-BackgroundWork
    $defs = foreach ($n in $portableFunctions) {
        $d = (Get-Command $n -CommandType Function -ErrorAction Stop).Definition
        "function $n {`r`n$d`r`n}"
    }
    # Scriptblocks must cross as TEXT - a scriptblock object drags its origin session state with it.
    $code = ($defs -join "`r`n") + "`r`n" + $Body.ToString()

    $script:rs = [runspacefactory]::CreateRunspace()
    $script:rs.Open()
    $script:rs.SessionStateProxy.SetVariable('sync', $sync)
    $script:ps = [powershell]::Create()
    $script:ps.Runspace = $script:rs
    $null = $script:ps.AddScript($code)
    $script:handle = $script:ps.BeginInvoke()
    $script:WorkerBusy = $true
    $script:timer.Start()
}

function Stop-BackgroundWork {
    if ($script:ps) {
        try { $script:ps.BeginStop($null, $null) } catch { }
        $sync.Done = $true
    }
}

function Complete-BackgroundWork {
    try {
        if ($script:handle) { $null = $script:ps.EndInvoke($script:handle) }
    } catch {
        if (-not $sync.CancelRequested) {
            Append-LogLine 'err' ('Worker error: ' + $_.Exception.Message)
        }
    }
    foreach ($obj in @($script:ps, $script:rs)) {
        if ($obj) { try { if ($obj -is [System.Management.Automation.PowerShell]) { $obj.Dispose() } else { $obj.Close(); $obj.Dispose() } } catch { } }
    }
    $script:ps = $null; $script:rs = $null; $script:handle = $null
    $script:WorkerBusy = $false

    if ($sync.Error) { Append-LogLine 'err' $sync.Error; $sync.Error = $null }

    if ($script:LastPhase -eq 'scanning') {
        Set-HeaderStatus $(if ($sync.SteamPath) { $sync.SteamPath } else { 'Steam not found' })
        try {
            if ($sync.SteamExe -and (Test-Path $sync.SteamExe)) {
                $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($sync.SteamExe)
                $script:form.Icon = $ico
                if (-not $script:SteamBmp) { $script:SteamBmp = $ico.ToBitmap() }
                $script:hdr.Invalidate()
            }
        } catch { }
        $script:lblProgress.Text = ''
        Apply-Filter
    }

    if ($script:LastPhase -eq 'iconcache') {
        $script:lblProgress.Text = 'Icon cache rebuilt'
    }

    $s = $sync.Summary
    if ($s) {
        Append-LogLine 'dim' '---------------------------------------------------------------'
        if ($s.Created -gt 0)       { Append-LogLine 'ok'   ('  Shortcuts created:    ' + $s.Created) }
        if ($s.Fixed -gt 0)         { Append-LogLine 'ok'   ('  Shortcuts repaired:   ' + $s.Fixed) }
        if ($s.OkCount -gt 0)       { Append-LogLine 'dim'  ('  Already up to date:   ' + $s.OkCount) }
        if ($s.OrphansRemoved -gt 0){ Append-LogLine 'warn' ('  Orphans removed:      ' + $s.OrphansRemoved) }
        if ($s.Failed -gt 0)        { Append-LogLine 'err'  ('  Failed / no icon:     ' + $s.Failed) }
        if ($s.Cancelled)           { Append-LogLine 'warn' '  Run cancelled' }
        Append-LogLine 'dim' '---------------------------------------------------------------'
        $sync.Summary = $null
        $script:lblProgress.Text = 'Done'
    }

    $sync.Phase = 'idle'
    $sync.CancelRequested = $false
    Set-BusyState $false
    Update-Counts
}

# =============================================================================
#  UI helpers (UI thread only)
# =============================================================================

$script:TFLeft   = [System.Windows.Forms.TextFormatFlags]::Left   -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::NoPadding -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis
$script:TFRight  = [System.Windows.Forms.TextFormatFlags]::Right  -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
$script:TFCenter = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::NoPadding

function Draw-Text {
    param($G, [string]$Text, $Font, [int]$X, [int]$Y, [int]$W, [int]$H, $Color, $Flags)
    if ($null -eq $Flags) { $Flags = $script:TFLeft }
    $r = New-Object System.Drawing.Rectangle($X, $Y, $W, $H)
    [System.Windows.Forms.TextRenderer]::DrawText($G, $Text, $Font, $r, $Color, $Flags)
}

function Measure-Text {
    param([string]$Text, $Font)
    return [System.Windows.Forms.TextRenderer]::MeasureText($Text, $Font).Width
}

# Right-aligned pill with an optional colored dot. Returns its left edge.
function Draw-Chip {
    param($G, [int]$Right, [int]$CenterY, [string]$Text, $Color, $Font, [bool]$Dot = $false, [int]$MaxWidth = 0, $DotColor = $null)
    if ($null -eq $DotColor) { $DotColor = $Color }
    $tw = Measure-Text $Text $Font
    if ($MaxWidth -gt 0 -and $tw -gt $MaxWidth) { $tw = $MaxWidth }
    $w = $tw + 24 + $(if ($Dot) { 14 } else { 0 })
    $h = 26
    $x = $Right - $w
    $r = New-Object System.Drawing.Rectangle($x, ($CenterY - 13), $w, $h)
    [SSF.Gfx]::Fill($G, $r, 13, [SSF.Pal]::Surface)
    [SSF.Gfx]::Stroke($G, $r, 13, [SSF.Pal]::BorderSoft, 1)
    $tx = $x + 12
    if ($Dot) {
        $b = New-Object System.Drawing.SolidBrush($DotColor)
        $G.FillEllipse($b, ($x + 12), ($r.Y + 10), 6, 6)
        $b.Dispose()
        $tx = $x + 26
    }
    Draw-Text $G $Text $Font $tx $r.Y ($tw + 2) $h $Color $script:TFLeft
    return $x
}

# Right-edge controls are positioned by hand (an Anchor would fight these handlers).
function Layout-Header {
    if (-not $script:btnRescan) { return }
    $script:btnRescan.Left = $script:hdr.ClientSize.Width - $script:btnRescan.Width - 18
    $script:btnIconDb.Left = $script:btnRescan.Left - $script:btnIconDb.Width - 8
    $script:hdr.Invalidate()
}

function Layout-Footer {
    if (-not $script:btnApply) { return }
    $script:btnApply.SetBounds(($script:pnlFooter.ClientSize.Width - 18 - $script:btnApply.Width), 20, $script:btnApply.Width, 38)
    $script:btnCancel.SetBounds(($script:btnApply.Left - 12 - $script:btnCancel.Width), 20, $script:btnCancel.Width, 38)
}

function Set-HeaderStatus {
    param([string]$Text)
    $script:HeaderStatus = $Text
    if ($script:hdr) { $script:hdr.Invalidate() }
}

function Append-LogLine {
    param([string]$Level, [string]$Text)
    $rtb = $script:rtbLog
    if (-not $rtb) { return }
    $color = switch ($Level) {
        'ok'   { $theme.Ok }
        'err'  { $theme.Err }
        'warn' { $theme.Warn }
        'dim'  { $theme.Faint }
        'info' { $theme.Dim }
        default { $theme.Text }
    }
    $rtb.SelectionStart = $rtb.TextLength
    $rtb.SelectionLength = 0
    $rtb.SelectionColor = $color
    $rtb.AppendText($Text + "`r`n")
    $rtb.SelectionColor = $rtb.ForeColor
    if ($rtb.TextLength -gt 300000) { $rtb.Text = $rtb.Text.Substring($rtb.TextLength - 150000) }
    $rtb.ScrollToCaret()
}

function Add-GameRow {
    param([hashtable]$VM)
    $row = New-Object SSF.GameRow
    $row.AppId          = [string]$VM.AppId
    $row.Name           = [string]$VM.Name
    $row.DesktopState   = [string]$VM.DesktopState
    $row.StartMenuState = [string]$VM.StartMenuState
    $row.IconState      = [string]$VM.IconState
    $row.NeedsFix       = [bool]$VM.NeedsFix
    $row.Checked        = [bool]$VM.NeedsFix     # sensible default: everything broken is pre-ticked
    $row.Thumb          = ConvertTo-Thumbnail -ImagePath $VM.ArtPath -Letter $VM.Name -TileSeed ([long]$VM.AppId) -Size 40
    $row.Tag            = $VM
    $script:lvGames.AddRow($row)
}

function Apply-Filter {
    if (-not $script:lvGames) { return }
    $script:lvGames.SetFilter($script:txtSearch.Query, $script:chkBrokenOnly.Checked)
    if ($script:lvGames.TotalCount -eq 0) {
        $script:lvGames.EmptyText = 'No games found'
        $script:lvGames.EmptyHint = 'Is Steam installed, with at least one game downloaded?'
    } else {
        $script:lvGames.EmptyText = 'Nothing matches this filter'
        $script:lvGames.EmptyHint = 'Try a different search, or untick "Only needs fixing"'
    }
    Update-Counts
}

function Update-Counts {
    if (-not $script:lvGames) { return }
    $sel = $script:lvGames.CheckedCount
    $script:btnApply.Text = $(if ($sel -eq 1) { 'Fix 1 game' } elseif ($sel -gt 0) { "Fix $sel games" } else { 'Fix selected' })
    if ($script:pnlToolbar) { $script:pnlToolbar.Invalidate() }
}

function Update-RowIcon {
    param([string]$AppId, [string]$IconPath)
    $row = $script:lvGames.Find($AppId)
    if (-not $row) { return }
    $old = $row.Thumb
    $row.Thumb = ConvertTo-Thumbnail -ImagePath $IconPath -Letter $row.Name -TileSeed ([long]$AppId) -Size 40
    if ($old) { $old.Dispose() }
    $script:lvGames.Invalidate()
}

function Update-RowResult {
    param([hashtable]$Res)
    $row = $script:lvGames.Find([string]$Res.AppId)
    if (-not $row) { return }

    $dk = $Res.Desktop; $mk = $Res.StartMenu
    if ($dk -eq 'created' -or $dk -eq 'fixed' -or $dk -eq 'ok') { $row.DesktopState = 'ok' }
    if ($mk -eq 'created' -or $mk -eq 'fixed' -or $mk -eq 'ok') { $row.StartMenuState = 'ok' }
    switch ($Res.Icon) {
        'downloaded' { $row.IconState = 'ok' }
        'kept'       { $row.IconState = 'ok' }
        'fallback'   { $row.IconState = 'fallback' }
        'fail'       { $row.IconState = 'broken' }
        'none'       { $row.IconState = 'fallback' }
    }
    $row.NeedsFix = (($row.DesktopState -ne 'ok') -or ($row.StartMenuState -ne 'ok') -or ($row.IconState -ne 'ok'))
    $script:lvGames.RowChanged($row)
    Update-Counts
}

function Set-BusyState {
    param([bool]$Busy)
    $script:btnApply.Enabled     = -not $Busy
    $script:btnRescan.Enabled    = -not $Busy
    $script:btnIconDb.Enabled    = -not $Busy
    $script:chkDesktop.Enabled   = -not $Busy
    $script:chkStartMenu.Enabled = -not $Busy
    $script:chkOrphans.Enabled   = -not $Busy
    $script:segCdn.Enabled       = -not $Busy
    $script:btnCancel.Enabled    = ($Busy -and $script:LastPhase -ne 'iconcache')
    $script:btnCancel.Text       = 'Cancel'
    if (-not $Busy) {
        $script:pbar.Marquee = $false
        $script:pbar.Value = 0
    }
}

# =============================================================================
#  Timer tick - the ONLY code that touches controls during background work
# =============================================================================

$timerTick = {
    $e = $null
    if ($script:WorkerBusy) {
        $n = 0
        $limit = $(if ($sync.Done) { [int]::MaxValue } else { 24 })
        $script:lvGames.BeginUpdate()
        while ($n -lt $limit -and $sync.GameQueue.TryDequeue([ref]$e)) { Add-GameRow $e; $n++ }
        $script:lvGames.EndUpdate()
        if ($n -gt 0) { Update-Counts }
        if ($sync.Done) { Complete-BackgroundWork }
        if ($sync.Phase -eq 'scanning' -and -not $sync.Done) {
            Set-HeaderStatus ('Scanning - ' + $script:lvGames.TotalCount + ' games found')
        }
    }
    while ($sync.IconUpdates.TryDequeue([ref]$e)) {
        Update-RowIcon -AppId $e.AppId -IconPath $e.IconPath
    }
    while ($sync.ResultQueue.TryDequeue([ref]$e)) { Update-RowResult $e }
    $drained = 0
    while ($drained -lt 200 -and $sync.LogQueue.TryDequeue([ref]$e)) {
        Append-LogLine $e.L $e.T
        $drained++
    }
    if ($sync.Phase -eq 'applying') {
        if ($script:pbar.Maximum -ne $sync.ProgressMax) { $script:pbar.Maximum = [Math]::Max(1, $sync.ProgressMax) }
        $script:pbar.Value = [Math]::Min($sync.ProgressValue, $sync.ProgressMax)
        $script:lblProgress.Text = $sync.ProgressValue.ToString() + ' / ' + $sync.ProgressMax.ToString() + '   ' + $sync.ProgressCurrent
    }
}

# =============================================================================
#  Form construction
# =============================================================================

function New-Panel {
    param([int]$Height = 0, $Back = $null)
    $p = New-Object SSF.SsfCard
    $p.Outline = $false
    $p.Radius = 0
    $p.BackColor = $(if ($Back) { $Back } else { [SSF.Pal]::Bg })
    if ($Height -gt 0) { $p.Height = $Height }
    return $p
}

function New-Btn {
    param([string]$Text, [int]$W, [int]$H, [string]$Kind = 'Secondary', [string]$Glyph = '')
    $b = New-Object SSF.SsfButton
    $b.Text = $Text
    $b.Variant = [SSF.SsfButton+Kind]::$Kind
    $b.Size = New-Object System.Drawing.Size($W, $H)
    if ($Glyph) { $b.Glyph = $Glyph }
    return $b
}

function New-Chk {
    param([string]$Text, [bool]$Checked = $true)
    $c = New-Object SSF.SsfCheck
    $c.Text = $Text
    $c.Checked = $Checked
    return $c
}

function Build-Form {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Steam Shortcut Fixer v2.0'
    $form.ClientSize = New-Object System.Drawing.Size(1160, 760)
    $form.MinimumSize = New-Object System.Drawing.Size(1000, 680)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = [SSF.Pal]::Bg
    $form.ForeColor = [SSF.Pal]::Text
    $form.Font = [SSF.Pal]::FUI
    $form.KeyPreview = $true

    # ------------------------------------------------------------------ header
    $hdr = New-Object SSF.SsfHeader
    $hdr.Dock = 'Top'
    $hdr.Height = 104

    $btnRescan = New-Btn -Text 'Rescan' -W 108 -H 34 -Kind 'Secondary' -Glyph ([char]0xE72C)
    $btnRescan.Location = New-Object System.Drawing.Point(0, 34)
    $hdr.Controls.Add($btnRescan)

    $btnIconDb = New-Btn -Text 'Rebuild icon cache' -W 166 -H 34 -Kind 'Secondary' -Glyph ([char]0xE117)
    $btnIconDb.Location = New-Object System.Drawing.Point(0, 34)
    $hdr.Controls.Add($btnIconDb)

    # credits + links, sitting under the subtitle
    $lnkAuthor = New-Object SSF.SsfLink
    $lnkAuthor.Text = 'abd3lraouf'
    $lnkAuthor.Url = 'https://github.com/abd3lraouf'
    $lnkAuthor.Normal = [SSF.Pal]::Accent
    $hdr.Controls.Add($lnkAuthor)

    $lnkRepo = New-Object SSF.SsfLink
    $lnkRepo.Text = 'Source on GitHub'
    $lnkRepo.Url = 'https://github.com/abd3lraouf/steam-icon-fixer'
    $hdr.Controls.Add($lnkRepo)

    $lnkIssue = New-Object SSF.SsfLink
    $lnkIssue.Text = 'Report an issue'
    $lnkIssue.Url = 'https://github.com/abd3lraouf/steam-icon-fixer/issues'
    $hdr.Controls.Add($lnkIssue)

    $lnkLicense = New-Object SSF.SsfLink
    $lnkLicense.Text = 'MIT License'
    $lnkLicense.Url = 'https://github.com/abd3lraouf/steam-icon-fixer/blob/main/LICENSE'
    $hdr.Controls.Add($lnkLicense)

    $script:HeaderLinks = @($lnkAuthor, $lnkRepo, $lnkIssue, $lnkLicense)
    $lx = 106
    foreach ($lnk in $script:HeaderLinks) {
        $lnk.Add_Click({ param($s, $e) if ($s.Url) { Start-Process $s.Url } })
        $lnk.SetBounds($lx, 71, $lnk.Width, 18)
        $lx += $lnk.Width + 24
    }

    $hdr.Add_Resize({ Layout-Header })

    $hdr.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

        $badge = New-Object System.Drawing.Rectangle(20, 24, 48, 48)
        for ($i = 7; $i -ge 1; $i--) {
            $gr = New-Object System.Drawing.Rectangle(($badge.X - $i), ($badge.Y - $i), ($badge.Width + $i * 2), ($badge.Height + $i * 2))
            [SSF.Gfx]::Stroke($g, $gr, (14 + $i), ([System.Drawing.Color]::FromArgb((5 + (8 - $i) * 4), [SSF.Pal]::Accent)), 2)
        }
        $bb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($badge, ([System.Drawing.Color]::FromArgb(18, 62, 100)), [SSF.Pal]::Accent, 45.0)
        $bp = [SSF.Gfx]::Round($badge, 14)
        $g.FillPath($bb, $bp)
        [SSF.Grain]::Apply($g, $bp, $true)
        $bb.Dispose(); $bp.Dispose()
        if ($script:SteamBmp) {
            $inner = New-Object System.Drawing.Rectangle(($badge.X + 8), ($badge.Y + 8), 32, 32)
            $g.DrawImage($script:SteamBmp, $inner)
        } else {
            Draw-Text $g 'S' ([SSF.Pal]::FTitle) $badge.X $badge.Y $badge.Width $badge.Height ([System.Drawing.Color]::White) $script:TFCenter
        }
        [SSF.Gfx]::Stroke($g, $badge, 14, ([System.Drawing.Color]::FromArgb(110, 255, 255, 255)), 1)

        # wordmark: fuchsia -> violet gradient text
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $tr = New-Object System.Drawing.Rectangle(84, 20, 520, 34)
        $tb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($tr, [SSF.Pal]::AccentHot, [SSF.Pal]::Accent2, 12.0)
        $g.DrawString('Steam Shortcut Fixer', [SSF.Pal]::FTitle, $tb, 82.0, 20.0)
        $tb.Dispose()
        Draw-Text $g 'Real .ico icons for your desktop and Start Menu shortcuts' ([SSF.Pal]::FSmall) 86 52 560 18 ([SSF.Pal]::Dim) $script:TFLeft

        # separators between the credit links
        Draw-Text $g 'by' ([SSF.Pal]::FSmall) 86 72 20 18 ([SSF.Pal]::Faint) $script:TFLeft
        foreach ($lnk in $script:HeaderLinks) {
            if ($lnk -ne $script:HeaderLinks[0]) {
                Draw-Text $g ([string][char]0x2022) ([SSF.Pal]::FSmall) ($lnk.Left - 12) 72 10 18 ([SSF.Pal]::Faint) $script:TFCenter
            }
        }

        $right = $script:btnIconDb.Left - 14
        $status = $(if ($script:HeaderStatus) { $script:HeaderStatus } else { 'Locating Steam...' })
        $dotCol = $(if ($script:WorkerBusy) { [SSF.Pal]::Warn } elseif ($script:HeaderStatus -like '*not found*') { [SSF.Pal]::Err } else { [SSF.Pal]::Ok })
        $null = Draw-Chip $g $right 51 $status ([SSF.Pal]::Dim) ([SSF.Pal]::FSmall) $true 380 $dotCol
    })

    # ----------------------------------------------------------------- toolbar
    $pnlToolbar = New-Panel -Height 60
    $pnlToolbar.Dock = 'Top'

    $txtSearch = New-Object SSF.SsfSearch
    $txtSearch.SetBounds(18, 13, 268, 34)
    $pnlToolbar.Controls.Add($txtSearch)

    $chkBrokenOnly = New-Chk -Text 'Only needs fixing' -Checked $false
    $chkBrokenOnly.Location = New-Object System.Drawing.Point(302, 17)
    $pnlToolbar.Controls.Add($chkBrokenOnly)

    $btnSelBroken = New-Btn -Text 'Select broken' -W 118 -H 30 -Kind 'Ghost'
    $btnSelBroken.Location = New-Object System.Drawing.Point(468, 15)
    $pnlToolbar.Controls.Add($btnSelBroken)

    $btnSelectAll = New-Btn -Text 'All' -W 62 -H 30 -Kind 'Ghost'
    $btnSelectAll.Location = New-Object System.Drawing.Point(590, 15)
    $pnlToolbar.Controls.Add($btnSelectAll)

    $btnSelectNone = New-Btn -Text 'None' -W 68 -H 30 -Kind 'Ghost'
    $btnSelectNone.Location = New-Object System.Drawing.Point(656, 15)
    $pnlToolbar.Controls.Add($btnSelectNone)

    $pnlToolbar.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        if (-not $script:lvGames) { return }
        $cy = 30
        $x = $s.ClientSize.Width - 18
        $fix = $script:lvGames.NeedsFixCount
        $x = Draw-Chip $g $x $cy ("$fix need fixing") $(if ($fix -gt 0) { [SSF.Pal]::Warn } else { [SSF.Pal]::Ok }) ([SSF.Pal]::FUIB) $true
        $x = Draw-Chip $g ($x - 8) $cy ($script:lvGames.CheckedCount.ToString() + ' selected') ([SSF.Pal]::Accent) ([SSF.Pal]::FUIB) $true
        $x = Draw-Chip $g ($x - 8) $cy ($script:lvGames.TotalCount.ToString() + ' games') ([SSF.Pal]::Dim) ([SSF.Pal]::FUIB) $false
    })

    # -------------------------------------------------------------- games list
    $pnlCenter = New-Panel
    $pnlCenter.Dock = 'Fill'
    $pnlCenter.Padding = New-Object System.Windows.Forms.Padding(18, 4, 18, 10)

    $cardList = New-Object SSF.SsfCard
    $cardList.Dock = 'Fill'
    $cardList.Radius = 12
    $cardList.Line = [SSF.Pal]::Border
    $cardList.Textured = $true

    $lvGames = New-Object SSF.SsfGameList
    $lvGames.Dock = 'Fill'
    $lvGames.EmptyText = 'Scanning your Steam libraries...'
    $lvGames.EmptyHint = 'This only takes a moment'
    $cardList.Controls.Add($lvGames)
    $pnlCenter.Controls.Add($cardList)

    # round off the card (and everything docked inside it)
    $cardList.Add_Resize({
        param($s, $e)
        $r = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
        $p = [SSF.Gfx]::Round($r, 12)
        $old = $s.Region
        $s.Region = New-Object System.Drawing.Region($p)
        $p.Dispose()
        if ($old) { $old.Dispose() }
    })

    $ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $ctxMenu.Renderer = New-Object SSF.DarkMenu
    $ctxMenu.BackColor = [SSF.Pal]::Elevated
    $ctxMenu.ForeColor = [SSF.Pal]::Text
    $ctxMenu.Font = [SSF.Pal]::FUI
    [void]$ctxMenu.Items.Add('Launch game')
    [void]$ctxMenu.Items.Add('Open shortcut folder')
    [void]$ctxMenu.Items.Add('Fix this game now')
    [void]$ctxMenu.Items.Add('-')
    [void]$ctxMenu.Items.Add('Tick')
    [void]$ctxMenu.Items.Add('Untick')
    $lvGames.ContextMenuStrip = $ctxMenu

    # ---------------------------------------------------------------- log card
    $pnlLogWrap = New-Panel -Height 178
    $pnlLogWrap.Dock = 'Bottom'
    $pnlLogWrap.Padding = New-Object System.Windows.Forms.Padding(18, 0, 18, 6)

    $cardLog = New-Object SSF.SsfCard
    $cardLog.Dock = 'Fill'
    $cardLog.Radius = 12
    $cardLog.Textured = $true
    $cardLog.Padding = New-Object System.Windows.Forms.Padding(14, 6, 14, 12)

    $rtbLog = New-Object System.Windows.Forms.RichTextBox
    $rtbLog.Dock = 'Fill'
    $rtbLog.ReadOnly = $true
    $rtbLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $rtbLog.BackColor = [SSF.Pal]::Surface
    $rtbLog.ForeColor = [SSF.Pal]::Text
    $rtbLog.Font = [SSF.Pal]::FMono
    $rtbLog.DetectUrls = $false
    $rtbLog.HideSelection = $false
    $rtbLog.Add_HandleCreated({ [SSF.Chrome]::DarkScroll($script:rtbLog.Handle) })
    $cardLog.Controls.Add($rtbLog)

    $pnlLogHead = New-Panel -Height 26 -Back ([SSF.Pal]::Surface)
    $pnlLogHead.Dock = 'Top'

    $btnLogClear = New-Btn -Text 'Clear' -W 58 -H 24 -Kind 'Ghost'
    $btnLogClear.Dock = 'Right'
    $pnlLogHead.Controls.Add($btnLogClear)

    $btnLogToggle = New-Btn -Text '' -W 30 -H 24 -Kind 'Ghost' -Glyph ([char]0xE70D)
    $btnLogToggle.Dock = 'Right'
    $pnlLogHead.Controls.Add($btnLogToggle)

    $pnlLogHead.Add_Paint({
        param($s, $e)
        Draw-Text $e.Graphics 'ACTIVITY LOG' ([SSF.Pal]::FHead) 2 0 200 $s.ClientSize.Height ([SSF.Pal]::Faint) $script:TFLeft
    })
    $cardLog.Controls.Add($pnlLogHead)
    $pnlLogWrap.Controls.Add($cardLog)

    $cardLog.Add_Resize({
        param($s, $e)
        $r = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
        $p = [SSF.Gfx]::Round($r, 12)
        $old = $s.Region
        $s.Region = New-Object System.Drawing.Region($p)
        $p.Dispose()
        if ($old) { $old.Dispose() }
    })

    # ---------------------------------------------------------------- progress
    $pnlProgress = New-Panel -Height 34
    $pnlProgress.Dock = 'Bottom'
    $pnlProgress.Padding = New-Object System.Windows.Forms.Padding(19, 12, 18, 12)

    $lblProgress = New-Object System.Windows.Forms.Label
    $lblProgress.Dock = 'Right'
    $lblProgress.Width = 380
    $lblProgress.AutoSize = $false
    $lblProgress.BackColor = [SSF.Pal]::Bg
    $lblProgress.ForeColor = [SSF.Pal]::Dim
    $lblProgress.Font = [SSF.Pal]::FSmall
    $lblProgress.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $lblProgress.Padding = New-Object System.Windows.Forms.Padding(0, 0, 2, 0)
    $pnlProgress.Controls.Add($lblProgress)

    $pbar = New-Object SSF.SsfProgress
    $pbar.Dock = 'Fill'
    $pnlProgress.Controls.Add($pbar)

    # ------------------------------------------------------------------ footer
    $pnlFooter = New-Panel -Height 74
    $pnlFooter.Dock = 'Bottom'
    $pnlFooter.Add_Paint({
        param($s, $e)
        $p = New-Object System.Drawing.Pen ([SSF.Pal]::BorderSoft)
        $e.Graphics.DrawLine($p, 18, 0, ($s.ClientSize.Width - 18), 0)
        $p.Dispose()
        Draw-Text $e.Graphics 'CREATE IN' ([SSF.Pal]::FHead) 20 12 200 14 ([SSF.Pal]::Faint) $script:TFLeft
        Draw-Text $e.Graphics 'ICON SOURCE' ([SSF.Pal]::FHead) $script:CdnLabelX 12 200 14 ([SSF.Pal]::Faint) $script:TFLeft
    })

    $chkDesktop   = New-Chk -Text 'Desktop'
    $chkStartMenu = New-Chk -Text 'Start Menu'
    $chkOrphans   = New-Chk -Text 'Remove orphaned shortcuts'
    $x = 18
    foreach ($c in @($chkDesktop, $chkStartMenu, $chkOrphans)) {
        $c.Location = New-Object System.Drawing.Point($x, 32)
        $pnlFooter.Controls.Add($c)
        $x += $c.Width + 20
    }
    $script:CdnLabelX = $x + 14

    $segCdn = New-Object SSF.SsfSegment
    $segCdn.Items = @('Fastly', 'Cloudflare')
    $segCdn.SelectedIndex = 0
    $segCdn.SetBounds(($x + 12), 31, 186, 30)
    $pnlFooter.Controls.Add($segCdn)

    $btnCancel = New-Btn -Text 'Cancel' -W 96 -H 38 -Kind 'Danger'
    $btnCancel.Enabled = $false
    $pnlFooter.Controls.Add($btnCancel)

    $btnApply = New-Btn -Text 'Fix selected' -W 178 -H 38 -Kind 'Primary' -Glyph ([char]0xE90F)
    $pnlFooter.Controls.Add($btnApply)

    $pnlFooter.Add_Resize({ Layout-Footer })

    # --- assemble (last docked wins the outer edge, so Fill goes in first) ----
    $form.Controls.Add($pnlCenter)
    $form.Controls.Add($pnlToolbar)
    $form.Controls.Add($hdr)
    $form.Controls.Add($pnlLogWrap)
    $form.Controls.Add($pnlProgress)
    $form.Controls.Add($pnlFooter)

    # ------------------------------------------------------ publish to script
    $script:form         = $form
    $script:hdr          = $hdr
    $script:pnlToolbar   = $pnlToolbar
    $script:pnlFooter    = $pnlFooter
    $script:lvGames      = $lvGames
    $script:ctxMenu      = $ctxMenu
    $script:txtSearch    = $txtSearch
    $script:chkBrokenOnly= $chkBrokenOnly
    $script:btnRescan    = $btnRescan
    $script:btnIconDb    = $btnIconDb
    $script:chkDesktop   = $chkDesktop
    $script:chkStartMenu = $chkStartMenu
    $script:chkOrphans   = $chkOrphans
    $script:segCdn       = $segCdn
    $script:btnApply     = $btnApply
    $script:btnCancel    = $btnCancel
    $script:pbar         = $pbar
    $script:lblProgress  = $lblProgress
    $script:rtbLog       = $rtbLog
    $script:pnlLogWrap   = $pnlLogWrap
    $script:btnLogToggle = $btnLogToggle
    $script:WorkerBusy   = $false
    $script:LastPhase    = ''
    $script:CancelClicks = 0
    $script:LogOpen      = $true

    # ------------------------------------------------------------------ events
    $txtSearch.Add_QueryChanged({ Apply-Filter })
    $chkBrokenOnly.Add_CheckedChanged({ Apply-Filter })

    $btnSelectAll.Add_Click({  $script:lvGames.SetVisibleChecked($true) })
    $btnSelectNone.Add_Click({ $script:lvGames.SetAllChecked($false) })
    $btnSelBroken.Add_Click({  $script:lvGames.CheckNeedsFix() })

    $lvGames.Add_CheckedChanged({ Update-Counts })
    $lvGames.Add_ItemActivate({
        $row = $script:lvGames.SelectedRow
        if ($row) { Start-Process ('steam://rungameid/' + $row.AppId) }
    })

    $ctxMenu.Add_ItemClicked({
        param($s, $ev)
        $row = $script:lvGames.SelectedRow
        if (-not $row) { return }
        switch ($ev.ClickedItem.Text) {
            'Launch game' { Start-Process ('steam://rungameid/' + $row.AppId) }
            'Open shortcut folder' {
                $cand = @(
                    (Join-Path $sync.DesktopDir ($row.Name + '.url')),
                    (Join-Path $sync.StartMenuDir ($row.Name + '.url'))
                )
                $target = $cand | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
                if ($target) { Start-Process explorer.exe ('/select,"' + $target + '"') }
                elseif ($sync.DesktopDir) { Start-Process explorer.exe $sync.DesktopDir }
            }
            'Fix this game now' {
                if ($script:WorkerBusy) { return }
                Start-Apply -AppIds @($row.AppId)
            }
            'Tick'   { $row.Checked = $true;  $script:lvGames.Invalidate(); Update-Counts }
            'Untick' { $row.Checked = $false; $script:lvGames.Invalidate(); Update-Counts }
        }
    })

    $btnLogClear.Add_Click({ $script:rtbLog.Clear() })
    $btnLogToggle.Add_Click({
        $script:LogOpen = -not $script:LogOpen
        if ($script:LogOpen) {
            $script:pnlLogWrap.Height = 178
            $script:rtbLog.Visible = $true
            $script:btnLogToggle.Glyph = [string][char]0xE70D
        } else {
            $script:rtbLog.Visible = $false
            $script:pnlLogWrap.Height = 46
            $script:btnLogToggle.Glyph = [string][char]0xE70E
        }
        $script:btnLogToggle.Invalidate()
    })

    $btnRescan.Add_Click({ if (-not $script:WorkerBusy) { Start-Scan } })
    $btnIconDb.Add_Click({ if (-not $script:WorkerBusy) { Start-IconCacheRebuild } })

    $btnApply.Add_Click({
        if ($script:WorkerBusy) { return }
        $sel = $script:lvGames.CheckedIds
        if ($sel.Count -eq 0) {
            Append-LogLine 'warn' 'Nothing selected - tick a game first (or use Select broken)'
            return
        }
        if (-not ($script:chkDesktop.Checked -or $script:chkStartMenu.Checked)) {
            Append-LogLine 'err' 'No destination selected - enable Desktop and/or Start Menu'
            return
        }
        Start-Apply -AppIds $sel
    })

    $btnCancel.Add_Click({
        if (-not $script:WorkerBusy) { return }
        if ($sync.Phase -eq 'cancelling' -or $script:CancelClicks -ge 1) {
            Append-LogLine 'warn' 'Forcing stop...'
            Stop-BackgroundWork
        } else {
            $sync.CancelRequested = $true
            $sync.Phase = 'cancelling'
            $script:CancelClicks++
            $script:btnCancel.Text = 'Force stop'
            Append-LogLine 'warn' 'Cancelling... (click again to force)'
        }
    })

    $form.Add_KeyDown({
        param($s, $ev)
        if ($ev.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            if ($script:WorkerBusy) { $script:btnCancel.PerformClick() } else { $script:form.Close() }
        } elseif ($ev.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
            if (-not $script:WorkerBusy) { Start-Scan }
        } elseif ($ev.Control -and $ev.KeyCode -eq [System.Windows.Forms.Keys]::F) {
            $script:txtSearch.Box.Focus()
        }
    })

    $form.Add_HandleCreated({ [SSF.Chrome]::DarkWindow($script:form.Handle) })

    $form.Add_FormClosing({
        param($s, $ev)
        if ($script:WorkerBusy) {
            $r = [System.Windows.Forms.MessageBox]::Show(
                'Work is still in progress. Close anyway?', 'Steam Shortcut Fixer',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { $ev.Cancel = $true; return }
            Stop-BackgroundWork
        }
        $script:timer.Stop()
    })

    $form.Add_Shown({
        [SSF.Chrome]::DarkWindow($script:form.Handle)
        Layout-Header
        Layout-Footer
        Append-LogLine 'dim' 'Steam Shortcut Fixer v2.0  -  by abd3lraouf'
        Append-LogLine 'info' 'Scanning installed games...'
        Start-Scan
    })

    return $form
}

# =============================================================================
#  Operations
# =============================================================================

function Start-Scan {
    $script:LastPhase = 'scanning'
    $script:CancelClicks = 0
    $script:lvGames.ClearRows()
    $script:lvGames.EmptyText = 'Scanning your Steam libraries...'
    $script:lvGames.EmptyHint = 'This only takes a moment'
    $sync.Games = @()
    $sync.InstalledIds = @()
    $sync.Done = $false
    $sync.CancelRequested = $false
    Set-BusyState $true
    Update-Counts
    $script:pbar.Marquee = $true
    $script:lblProgress.Text = 'Scanning...'
    Start-BackgroundWork -Body $scanBody
}

function Start-IconCacheRebuild {
    $msg = @'
Rebuild the Windows icon cache?

Windows keeps its own database of every icon it has drawn, and a stale entry
is why a fixed shortcut can still look wrong. Rebuilding it will:

  - close and restart Windows Explorer (your taskbar will blink)
  - delete IconCache.db and iconcache_*.db
  - let Windows redraw every icon from scratch

Nothing in Steam, and none of your files, are touched.
'@
    $r = [System.Windows.Forms.MessageBox]::Show($msg, 'Rebuild icon cache',
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($r -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $script:LastPhase = 'iconcache'
    $script:CancelClicks = 0
    $sync.Done = $false
    $sync.CancelRequested = $false
    $sync.Summary = $null
    Set-BusyState $true
    $script:pbar.Marquee = $true
    $script:lblProgress.Text = 'Rebuilding icon cache...'
    Start-BackgroundWork -Body $iconCacheBody
}

function Start-Apply {
    param([string[]]$AppIds)
    $script:LastPhase = 'applying'
    $script:CancelClicks = 0
    $sync.SelectedAppIds = $AppIds
    $sync.DestDesktop   = $script:chkDesktop.Checked
    $sync.DestStartMenu = $script:chkStartMenu.Checked
    $sync.RemoveOrphans = $script:chkOrphans.Checked
    if ($script:segCdn.SelectedIndex -eq 1) {
        $sync.CdnBase = 'https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps'
        $sync.CdnName = 'Cloudflare'
    } else {
        $sync.CdnBase = 'https://shared.fastly.steamstatic.com/community_assets/images/apps'
        $sync.CdnName = 'Fastly'
    }
    if (-not $sync.SteamPath) {
        Append-LogLine 'err' 'Steam was not found yet - wait for the scan to finish'
        return
    }
    Append-LogLine 'info' ('Applying to ' + $AppIds.Count + ' game(s)  -  CDN: ' + $sync.CdnName)
    $sync.Done = $false
    $sync.CancelRequested = $false
    $sync.ProgressMax = $AppIds.Count
    $sync.ProgressValue = 0
    $sync.Summary = $null
    Set-BusyState $true
    $script:pbar.Marquee = $false
    $script:pbar.Maximum = [Math]::Max(1, $AppIds.Count)
    $script:pbar.Value = 0
    Start-BackgroundWork -Body $applyBody
}

# =============================================================================
#  Entry point
# =============================================================================

$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 100
$script:timer.Add_Tick($timerTick)

[void](Build-Form)
Append-LogLine 'dim' 'Initializing...'
[void]$script:form.ShowDialog()
$script:timer.Stop()
