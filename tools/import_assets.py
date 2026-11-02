#!/usr/bin/env python3
"""Copies Telegram's own icons out of submodules/TelegramUI/Images.xcassets
into Resources/ as @1x/@2x PNGs that iOS 6 can load with +imageNamed:.

PDF assets are rasterized with poppler's pdftocairo at 72 and 144 dpi
(1pt = 1px at @1x), PNG assets are copied from their @2x file and
downscaled for @1x. Nothing is redrawn: these are the original artwork.
Run from the project directory after changing ASSETS.
"""
import glob
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
XCASSETS = os.path.join(ROOT, "submodules", "TelegramUI", "Images.xcassets")
OUT = os.path.abspath(os.path.join(HERE, "..", "Resources"))

# output name -> asset path inside Images.xcassets
ASSETS = {
    "tab_chats": "Chat List/Tabs/IconChats",
    "tab_contacts": "Chat List/Tabs/IconContacts",
    "tab_calls": "Chat List/Tabs/IconCalls",
    "tab_settings": "Chat List/Tabs/IconSettings",
    "nav_compose": "Chat List/ComposeIcon",
    "nav_back": "Navigation/Back",
    "list_muted": "Chat List/PeerMutedIcon",
    "list_pinned": "Chat List/PeerPinnedIcon",
    "list_search": "Chat List/SearchIcon",
    "list_call_in": "Chat List/CallIncomingIcon",
    "list_call_out": "Chat List/CallOutgoingIcon",
    "list_disclosure": "Item List/DisclosureArrow",
    "input_attach": "Chat/Input/Text/IconAttachment",
    "input_mic": "Chat/Input/Text/IconMicrophone",
    "input_send": "Chat/Input/Text/SendIcon",
    "input_stickers": "Chat/Input/Text/AccessoryIconStickers",
    "avatar_saved": "Avatar/SavedMessagesIcon",
    "contacts_add": "Contact List/AddMemberIcon",
    "contacts_invite": "Contact List/InviteActionIcon",
    "settings_gradient": "Item List/Icons/Gradient",
    "settings_backdrop": "Item List/Icons/Backdrop",
    "settings_saved": "Item List/Icons/SavedMessages",
    "settings_phone": "Item List/Icons/Phone",
    "settings_devices": "Item List/Icons/Devices",
    "settings_folder": "Item List/Icons/Folder",
    "settings_notifications": "Item List/Icons/Notifications",
    "settings_privacy": "Item List/Icons/Privacy",
    "settings_data": "Item List/Icons/Data",
    "settings_appearance": "Item List/Icons/Appearance",
    "settings_power": "Item List/Icons/PowerSaving",
    "settings_language": "Item List/Icons/Language",
    "settings_support": "Item List/Icons/Support",
    "settings_faq": "Item List/Icons/Faq",
    "settings_tips": "Item List/Icons/Tips",
}


def rasterize_pdf(pdf, dpi, dest):
    with tempfile.TemporaryDirectory() as tmp:
        base = os.path.join(tmp, "out")
        subprocess.run(["pdftocairo", "-png", "-transp", "-singlefile", "-r", str(dpi), pdf, base], check=True)
        shutil.move(base + ".png", dest)


def main():
    for name, asset in ASSETS.items():
        folder = os.path.join(XCASSETS, asset + ".imageset")
        pdfs = glob.glob(os.path.join(folder, "*.pdf"))
        out1 = os.path.join(OUT, name + ".png")
        out2 = os.path.join(OUT, name + "@2x.png")
        if pdfs:
            rasterize_pdf(pdfs[0], 72, out1)
            rasterize_pdf(pdfs[0], 144, out2)
        else:
            src = glob.glob(os.path.join(folder, "*@2x.png"))
            if not src:
                sys.exit("no @2x png or pdf in " + folder)
            shutil.copyfile(src[0], out2)
            img = Image.open(out2)
            img.resize((max(1, img.width // 2), max(1, img.height // 2)), Image.LANCZOS).save(out1)
        print(name, Image.open(out1).size)


main()
