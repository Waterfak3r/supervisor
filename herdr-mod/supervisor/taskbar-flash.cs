// Herdr 有事等你时让任务栏按钮像微信一样常亮（橙色、不闪）。由 attention.js 调用；缺 exe 时 attention.js 会用系统自带的 csc 编译本文件。
//   taskbar-flash.exe          高亮 herdr-app 的任务栏按钮，切到 Herdr 后自动消失（Herdr 已在前台则什么都不做）
//   taskbar-flash.exe --stop   取消高亮
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

static class TaskbarFlash
{
    [StructLayout(LayoutKind.Sequential)]
    struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }

    [DllImport("user32.dll")] static extern bool FlashWindowEx(ref FLASHWINFO info);
    [DllImport("user32.dll")] static extern bool FlashWindow(IntPtr hwnd, bool invert);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();

    const uint FLASHW_STOP = 0;

    static int Main(string[] args)
    {
        bool stop = args.Length > 0 && args[0] == "--stop";
        int flashed = 0, skipped = 0;
        foreach (Process p in Process.GetProcessesByName("herdr-app"))
        {
            IntPtr hwnd = p.MainWindowHandle;
            if (hwnd == IntPtr.Zero) continue;
            if (!stop && hwnd == GetForegroundWindow()) { skipped++; continue; }
            if (stop)
            {
                FLASHWINFO info = new FLASHWINFO();
                info.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO));
                info.hwnd = hwnd;
                info.dwFlags = FLASHW_STOP;
                FlashWindowEx(ref info);
            }
            else
            {
                // 只翻转一次：任务栏按钮变橙并保持，不再闪
                FlashWindow(hwnd, true);
            }
            flashed++;
        }
        Console.WriteLine((stop ? "stopped " : "highlighted ") + flashed + (skipped > 0 ? " (foreground, skipped " + skipped + ")" : ""));
        return 0;
    }
}
