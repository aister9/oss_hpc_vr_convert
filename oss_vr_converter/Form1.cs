using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Runtime.InteropServices;

namespace oss_vr_converter
{
    public partial class Form1 : Form
    {
        public Form1()
        {
            InitializeComponent();
        }

        [DllImport("CudaVRconvertDLL.dll", CallingConvention = CallingConvention.Cdecl)]
        unsafe extern public static void test(char[] filepath, StringBuilder properties);

        [DllImport("CudaVRconvertDLL.dll", CallingConvention = CallingConvention.Cdecl)]
        unsafe extern public static void runAVI(char[] filepath);

        private void label1_Click(object sender, EventArgs e)
        {

        }

        //Click "파일선택"버튼
        private void button1_Click(object sender, EventArgs e)
        {
            OpenFileDialog openFileDig = new OpenFileDialog();
            openFileDig.DefaultExt = "avi";
            openFileDig.Filter = "Video Files(*.avi)|*.avi";
            openFileDig.ShowDialog();

            if(openFileDig.FileName.Length > 0)
            {
                foreach(string filename in openFileDig.FileNames)
                    this.textBox1.Text = filename;
            }
            StringBuilder strb = new StringBuilder();
            test(this.textBox1.Text.ToCharArray(), strb);
            this.label2.Text = strb.ToString();
        }

        private void Form1_Load(object sender, EventArgs e)
        {

        }

        private void button2_Click(object sender, EventArgs e)
        {
            if (this.textBox1.Text == null) return;

            runAVI(this.textBox1.Text.ToCharArray());
        }
    }
}
