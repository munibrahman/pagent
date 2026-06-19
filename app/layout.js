import { Hedvig_Letters_Serif, Inter, Lato } from "next/font/google";
import "./globals.css";

// Headers
const hedvig = Hedvig_Letters_Serif({
  variable: "--font-hedvig",
  subsets: ["latin"],
  weight: ["400"],
});

// Everything else
const lato = Lato({
  variable: "--font-lato",
  subsets: ["latin"],
  weight: ["300", "400", "700", "900"],
});

// Wordmark / brand
const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
});

export const metadata = {
  title: "PartsPanda — the parts counter that never misses a call",
  description:
    "PartsPanda answers every call to your auto parts counter, checks real inventory, and quotes price and availability 24/7.",
};

export default function RootLayout({ children }) {
  return (
    <html
      lang="en"
      className={`${hedvig.variable} ${lato.variable} ${inter.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
