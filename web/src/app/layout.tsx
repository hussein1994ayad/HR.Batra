import type { Metadata } from "next";
import { Cairo } from "next/font/google";
import "./globals.css";
import "leaflet/dist/leaflet.css";

const cairo = Cairo({
  subsets: ["arabic", "latin"],
  weight: ["300", "400", "500", "600", "700", "800", "900"],
  variable: "--font-cairo",
});

export const metadata: Metadata = {
  title: "HR Pro v6.0 - لوحة التحكم الاحترافية للمدير 👑",
  description: "نظام إدارة الموارد البشرية والتحليلات المتقدم والتتبع الجغرافي للموظفين",
};

export const viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
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
      <body className="min-h-full font-sans bg-[#090D16] text-[#F8FAFC] selection:bg-teal-500/30 selection:text-teal-200 overflow-x-hidden">
        {children}
      </body>
    </html>
  );
}
