using System;
using System.Drawing;
using System.Text;
using System.Windows.Forms;
namespace CodexLockGuardNotification {
    internal static class IdentityAlert {
        [STAThread]
        private static int Main(string[] args) {
            if(args.Length!=2) return 2;
            string text,title;
            try { text=Encoding.Unicode.GetString(Convert.FromBase64String(args[0]));title=Encoding.Unicode.GetString(Convert.FromBase64String(args[1])); }
            catch(FormatException) {return 3;}
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using(Form window=new Form()) {
                window.Text=title;window.StartPosition=FormStartPosition.CenterScreen;
                window.Size=new Size(750,440);window.MinimumSize=new Size(620,340);
                window.ShowInTaskbar=true;window.TopMost=true;window.Icon=SystemIcons.Warning;
                window.MinimizeBox=false;window.MaximizeBox=false;window.Padding=new Padding(20);
                TextBox body=new TextBox();body.Text=text;body.Multiline=true;body.ReadOnly=true;
                body.BorderStyle=BorderStyle.None;body.BackColor=SystemColors.Control;
                body.Font=new Font("Segoe UI",11);body.ScrollBars=ScrollBars.Vertical;body.Dock=DockStyle.Fill;
                Button ok=new Button();ok.Text="Tamam";ok.Size=new Size(110,36);
                FlowLayoutPanel footer=new FlowLayoutPanel();footer.Dock=DockStyle.Bottom;
                footer.Height=48;footer.FlowDirection=FlowDirection.RightToLeft;footer.Controls.Add(ok);
                ok.Click+=delegate {window.Close();};window.AcceptButton=ok;
                window.Controls.Add(body);window.Controls.Add(footer);
                Application.Run(window);
            }
            return 0;
        }
    }
}
