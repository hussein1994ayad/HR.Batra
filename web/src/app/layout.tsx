import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import "./globals.css";

// خط Cairo من ملفات داخل المشروع (رخصة OFL في fonts/OFL.txt): البناء كان يحمّله من
// Google Fonts وقت الـ build، وإذا فشل التحميل على سيرفر GitHub يفشل بناء الموقع كله.
const cairo = localFont({
  src: [
    { path: "./fonts/Cairo-Regular.ttf", weight: "400", style: "normal" },
    { path: "./fonts/Cairo-Medium.ttf", weight: "500", style: "normal" },
    { path: "./fonts/Cairo-SemiBold.ttf", weight: "600", style: "normal" },
    { path: "./fonts/Cairo-Bold.ttf", weight: "700", style: "normal" },
    { path: "./fonts/Cairo-ExtraBold.ttf", weight: "800", style: "normal" },
    { path: "./fonts/Cairo-Black.ttf", weight: "900", style: "normal" },
  ],
  display: "swap",
  variable: "--font-cairo",
});

export const metadata: Metadata = {
  title: "HR Pro — لوحة تحكم الموارد البشرية",
  description: "نظام إدارة الموارد البشرية والتحليلات المتقدم والتتبع الجغرافي للموظفين",
  manifest: "/manifest.json",
  applicationName: "HR Pro",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "HR Pro",
  },
  icons: {
    icon: [
      { url: "/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [
      { url: "/icon-192.png", sizes: "192x192", type: "image/png" },
    ],
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#070B14",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="ar"
      dir="rtl"
      className={`${cairo.variable} h-full antialiased`}
    >
      <body className="min-h-full font-sans bg-dark-bg text-slate-50 overflow-x-hidden">
        {children}
      </body>
    </html>
  );
}
