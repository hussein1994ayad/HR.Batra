import type { Metadata } from "next";
import { Cairo } from "next/font/google";
import "./globals.css";
import "leaflet/dist/leaflet.css";

const cairo = Cairo({
  subsets: ["arabic", "latin"],
  weight: ["400", "500", "600", "700", "800", "900"],
  display: "swap",
  variable: "--font-cairo",
});

export const metadata: Metadata = {
  title: "HR Pro — لوحة تحكم الموارد البشرية",
  description: "نظام إدارة الموارد البشرية والتحليلات المتقدم والتتبع الجغرافي للموظفين",
};

export const viewport = {
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
