# Desktop renderer adapted from SametDuhan/claude-done-pixel (MIT).
param(
    [ValidateRange(2,12)][double]$Scale = 4,
    [ValidateRange(0.25,4)][double]$Speed = 1,
    [string]$RenderPreview = '',
    [switch]$CompileOnly
)
$ErrorActionPreference = 'Stop'
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class ChatGPTDonePixel : Form {
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    const int Transparent = 0x20, ToolWindow = 0x80, NoActivate = 0x08000000, Topmost = 0x8;
    public const double Arrive = 0.8, Jump = 0.65, Grow = 0.35, Wave = 0.9, Hold = 0.65, Exit = 0.8;
    public const double Duration = Arrive + 2*Jump + Grow + 2*Wave + Hold + Exit;
    static readonly Color Key = Color.Magenta;
    static readonly Brush Badge = new SolidBrush(Color.FromArgb(16, 143, 117));
    static readonly Brush Edge = new SolidBrush(Color.FromArgb(5, 87, 73));
    static readonly Brush White = new SolidBrush(Color.FromArgb(250, 255, 253));
    static readonly Brush Arm = new SolidBrush(Color.FromArgb(183, 226, 215));
    static readonly Brush Green = new SolidBrush(Color.FromArgb(58, 231, 104));
    static readonly Brush GreenDark = new SolidBrush(Color.FromArgb(20, 162, 69));
    static readonly Brush Shadow = new SolidBrush(Color.FromArgb(45, 58, 55));
    static readonly bool[,] Logo = MakeLogo();
    readonly Timer timer = new Timer();
    readonly Stopwatch elapsed = new Stopwatch();
    readonly double speed;
    readonly int u;
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { var cp = base.CreateParams; cp.ExStyle |= Transparent | ToolWindow | NoActivate | Topmost; return cp; }
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x84) { m.Result = new IntPtr(-1); return; } // HTTRANSPARENT
        if (m.Msg == 0x21) { m.Result = new IntPtr(3); return; }  // MA_NOACTIVATE
        base.WndProc(ref m);
    }
    public ChatGPTDonePixel(double scale, double rate) {
        SetProcessDPIAware(); speed = rate;
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
        StartPosition = FormStartPosition.Manual; BackColor = Key; TransparencyKey = Key; DoubleBuffered = true;
        using (Graphics g = CreateGraphics()) u = Math.Max(2, (int)Math.Round(scale*g.DpiX/96));
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        int w = 80*u, h = 68*u;
        Bounds = new Rectangle(wa.Right-w, wa.Bottom-h-8, w, h);
        timer.Interval = 16;
        timer.Tick += delegate { Invalidate(); if (elapsed.Elapsed.TotalSeconds*speed >= Duration) Close(); };
        Shown += delegate { elapsed.Start(); timer.Start(); };
    }
    protected override void Dispose(bool disposing) {
        if (disposing) { timer.Stop(); timer.Dispose(); }
        base.Dispose(disposing);
    }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.Clear(Key);
        Draw(e.Graphics, elapsed.Elapsed.TotalSeconds*speed, u, ClientSize.Width, ClientSize.Height);
    }
    static void R(Graphics g, Brush b, int cx, int cy, int x, int y, int w, int h, int px) {
        g.FillRectangle(b, cx+x*px, cy+y*px, w*px, h*px);
    }
    static double Ease(double p) { p = Math.Max(0, Math.Min(1,p)); return 1-Math.Pow(1-p,3); }
    public static void Draw(Graphics g, double t, int px, int width, int height) {
        g.SmoothingMode = SmoothingMode.None; g.PixelOffsetMode = PixelOffsetMode.None;
        double landed = Arrive+2*Jump, grown = landed+Grow, waved = grown+2*Wave;
        double stop = width-56*px, start = width+4*px, x = stop, y = 0, arms = 0, sway = 0;
        if (t < Arrive) x = start+(stop-start)*Ease(t/Arrive);
        else if (t < landed) y = -Math.Sin(((t-Arrive)%Jump)/Jump*Math.PI)*18*px;
        else if (t < grown) arms = Ease((t-landed)/Grow);
        else { arms = 1; if (t < waved) sway = Math.Sin((t-grown)/Wave*2*Math.PI); }
        if (t > waved+Hold) x += (start-stop)*Math.Pow(Math.Min(1,(t-waved-Hold)/Exit),2);
        int ground = height-5*px, cx = (int)Math.Round(x), cy = ground-32*px+(int)Math.Round(y/px)*px;
        g.FillRectangle(Shadow,cx+7*px,ground+px,18*px,px);
        if (arms > 0) {
            int reach = (int)Math.Round(10*arms);
            int lift = (int)Math.Round(sway*2);
            // Two arms emerge only after the second landing.
            R(g,Arm,cx,cy,-reach,17-lift,reach,3,px);
            R(g,Arm,cx,cy,-reach,11-lift,3,8,px);
            R(g,Arm,cx,cy,32,17+lift,reach,3,px);
            R(g,Arm,cx,cy,29+reach,11+lift,3,8,px);
            if (arms > 0.65) {
                Flag(g,cx,cy,-reach+1,12-lift,-1,sway,px);
                Flag(g,cx,cy,30+reach,12+lift,1,-sway,px);
            }
        }
        // Stepped corners: every visible mark is an integer-sized pixel rectangle.
        R(g,Edge,cx,cy,4,1,24,32,px); R(g,Edge,cx,cy,1,5,30,24,px);
        R(g,Badge,cx,cy,4,0,24,32,px); R(g,Badge,cx,cy,2,2,28,28,px); R(g,Badge,cx,cy,0,4,32,24,px);
        for (int iy=0;iy<32;iy++) for (int ix=0;ix<32;ix++)
            if (Logo[ix,iy]) R(g,White,cx,cy,ix,iy,1,1,px);
        if (t >= grown && t < waved+Hold) {
            // Tiny celebratory pixels, away from the clock.
            R(g,Green,cx,cy,-4,-6,2,2,px); R(g,White,cx,cy,36,-9,2,2,px);
        }
    }
    static void Flag(Graphics g,int cx,int cy,int pole,int bottom,int side,double wave,int px) {
        int lean = (int)Math.Round(wave*3), top = bottom-15;
        for(int k=0;k<16;k++) R(g,White,cx,cy,pole+(int)Math.Round(lean*k/15.0),bottom-k,1,1,px);
        for(int row=0;row<7;row++) {
            int ripple = (int)Math.Round(Math.Sin(row*.9+wave*2));
            int left = side < 0 ? pole+lean-9+ripple : pole+lean+1;
            R(g,row==6?GreenDark:Green,cx,cy,left,top+row,9,1,px);
        }
        R(g,White,cx,cy,pole+lean,top-1,1,1,px);
    }
    // One strand of the OpenAI knot (see assets/SOURCE.md); rotate it six times.
    static GraphicsPath Strand() {
        var p = new GraphicsPath(FillMode.Alternate);
        p.StartFigure();
        p.AddBezier(1107.3f,299.1f,909.301f,299.1f,733.4f,426.4f,672.1f,614.4f);
        p.AddLine(672.1f,614.4f,650,743.5f); p.AddLine(650,743.5f,650,1171.4f);
        p.AddBezier(650,1171.4f,650,1192.8f,661,1211.8f,679.4f,1222.8f);
        p.AddLine(679.4f,1222.8f,1023.9f,1421.315f); p.AddLine(1023.9f,1421.315f,1023.9f,833.3f);
        p.AddLine(1023.9f,833.3f,1024,833.3f); p.AddLine(1024,833.3f,1024,805.4f);
        p.AddLine(1024,805.4f,1372.7f,604);
        p.AddBezier(1372.7f,604,1406.415f,584.48f,1443.14f,571.143f,1481.17f,564.172f);
        p.AddLine(1481.17f,564.172f,1447.6f,450.3f);
        p.AddBezier(1447.6f,450.3f,1361,353.5f,1237.1f,298.5f,1107.3f,299.1f); p.CloseFigure();
        p.StartFigure(); p.AddLine(1107.3f,416.6f,1106.7f,417.2f);
        p.AddBezier(1106.7f,417.2f,1186.399f,417.2f,1263,444.7f,1324.3f,495.6f);
        p.AddBezier(1324.3f,495.6f,1321.8f,496.8f,1316.9f,499.9f,1313.3f,501.7f);
        p.AddLine(1313.3f,501.7f,952.8f,709.3f);
        p.AddBezier(952.8f,709.3f,934.4f,719.7f,923.4f,739.3f,923.4f,760.7f);
        p.AddLine(923.4f,760.7f,923.4f,1248); p.AddLine(923.4f,1248,768.3f,1158.6f);
        p.AddLine(768.3f,1158.6f,768.3f,755.8f);
        p.AddBezier(768.3f,755.8f,768.2f,568.701f,919.901f,416.9f,1107.3f,416.6f); p.CloseFigure();
        return p;
    }
    static bool[,] MakeLogo() {
        bool[,] result = new bool[32,32];
        using (Bitmap mask = new Bitmap(32,32)) using (Graphics g = Graphics.FromImage(mask)) {
            g.Clear(Color.Black); g.SmoothingMode = SmoothingMode.None;
            g.ScaleTransform(32f/2406,32f/2406);
            for (int i=0;i<6;i++) {
                var state = g.Save(); g.TranslateTransform(1203,1203); g.RotateTransform(60*i); g.TranslateTransform(-1203,-1203);
                using (var strand = Strand()) g.FillPath(Brushes.White,strand); g.Restore(state);
            }
            for(int y=0;y<32;y++) for(int x=0;x<32;x++) result[x,y]=mask.GetPixel(x,y).R>128;
        }
        return result;
    }
    public static void Preview(string path) {
        string[] labels = { "ARRIVE", "JUMP 1", "JUMP 2", "TWO FLAGS", "WAVE", "DONE" };
        double[] times = { Arrive, Arrive+Jump/2, Arrive+1.5*Jump, Arrive+2*Jump+Grow+.05, Arrive+2*Jump+Grow+.25*Wave, Duration-Exit-.1 };
        int panel=320, height=308;
        using(var bmp = new Bitmap(panel*6,height)) using(var g = Graphics.FromImage(bmp)) using(var font=new Font("Consolas",11,FontStyle.Bold)) {
            g.Clear(Color.FromArgb(19,26,27));
            for(int i=0;i<6;i++) {
                var s=g.Save(); g.TranslateTransform(panel*i,0);
                Draw(g,times[i],4,panel,272); g.DrawString(labels[i],font,Brushes.White,18,284); g.Restore(s);
            }
            bmp.Save(path,ImageFormat.Png);
        }
    }
}
'@
if ($CompileOnly) { return }
if ($RenderPreview) {
    [ChatGPTDonePixel]::Preview([System.IO.Path]::GetFullPath($RenderPreview))
    return
}
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\ChatGPTDonePixel', [ref]$created)
if (-not $created) { $mutex.Dispose(); return }
try {
    $form = New-Object ChatGPTDonePixel -ArgumentList $Scale, $Speed
    try { [System.Windows.Forms.Application]::Run($form) } finally { $form.Dispose() }
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
