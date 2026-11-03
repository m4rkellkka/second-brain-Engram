import type { ComponentType, SVGProps } from "react";
import { FolderClosed, Inbox, MessageCircle, Mic } from "lucide-react";
import { EngramMark } from "./engram-mark";

export type NavItem = {
  href: string;
  label: string;
  icon: ComponentType<SVGProps<SVGSVGElement>>;
};

/** Main navigation, in the order of the mobile tab bar from the mockups. */
export const NAV_ITEMS: readonly NavItem[] = [
  { href: "/capture", label: "Capture", icon: Mic },
  { href: "/inbox", label: "Inbox", icon: Inbox },
  { href: "/brain", label: "Brain", icon: EngramMark },
  { href: "/projects", label: "Projects", icon: FolderClosed },
  { href: "/ask", label: "Ask", icon: MessageCircle },
];

export function isActive(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`);
}
