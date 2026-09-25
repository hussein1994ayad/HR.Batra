import type { Metadata, Viewport } from "next";
import { Cairo } from "next/font/google";
import "./globals.css";

const cairo = Cairo({
  subsets: ["arabic", "latin"],
  weight: ["400", "500", "600", "700", "800", "900"],
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
