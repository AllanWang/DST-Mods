# DST Development

This page offers a quick summary of what to do to get started.
A lot of other guides are either outdated or focus on the development process alone, so hopefully this will fill in the gap.
The tutorial is geared towards macOS.

## Environment

Mods are developed using Lua. There are some other languages that compile down to it, but they are either very different or don't have great tooling.
Given that the DST source code and other examples are all in Lua, I would recommend you stick with it if you are new to all language options. 
You can see some quick samples via [learn x in y minutes](https://learnxinyminutes.com/docs/lua/).

Klei also has a `.tex` file format for textures. It is hard to find info about this without seeing LaTeX, but here are some sample tools:

* [ztools](https://gitlab.com/Zarklord/ztools) (Cross platform)
* [ktool](https://github.com/nsimplex/ktools) (Cross platform)
* [TexTool](https://github.com/HandsomeMatt/dont-starve-tools) (Windows)

## Mod Format

In short, a mod requires `modinfo.lua` for metadata and `modmain.lua` for actual code.
You can take a look at any small mod for details.

## Source Code

Code is available at

```
~/Library/Application Support/Steam/steamapps/common/Don't Starve Together/dontstarve_steam.app/Contents
```

(Right click DST > Options > Show in Finder > Right click file > Show Package Contents > ...)

---

Mods are in the `mods` folder. If you subscribe to a workshop and open steam, it'll be copied here.
For development, you can make a new folder locally.

---

Sources are zipped at `data/databundles/scripts.zip`. You can see `data/scripts_readme.txt` for details in case this changes.
For the most part, you don't need to modify these files, so feel free to unzip it anywhere. For me, I put all sources in `source` under this project root; the folder is gitignored.

## Mod Development

This is where the other docs shine. 
Feel free to visit the [Klei Forum](https://forums.kleientertainment.com/forums/forum/247-tutorials-and-guides/), or learn from other mods.

In short, DST is very open, and you can look at the source code to find which global functions to override.

### General tips

I've only used Lua for a short time, but some tips that may help:

* Call function "supers" when overriding. If modifying `function T:a`, create `local a_base = T.a`. When creating a new `function T:a`, call `a_base` somewhere so that the behaviour remains consistent for the application and other mods.
* Nil check before calling fields. If calling `a.b.c`, check that `a ~= nil and b ~= nil` first. If `b` exists, calling `b.c` when `c` does not exist will return nil, so you don't have to worry about types or a defined function in that case.
* Avoid generic global field names. Introducing new fields may clash with the source code or any of the other mods available. Consider adding a prefix, and moving your fields into a separate prefixed key if you have a lot of them.

## Mod Testing

I test mods by creating a dev copy under the `dontstarve_steam.app/Contents/mods` folder. 
Only `modmain.lua` changes for me so I create a hard link (eg `ln [projectDir]/[modName]/mod/modmain.lua [absoluteDirToDstContents]/mods/[modName]-dev/modmain.lua)`; for `modinfo.lua`, I will add a suffix to the mod name.
Now, you can edit the mod file in git and have it automatically applied whenever the server starts.

Testing the mod requires a server restart, which can either be done with `c_reset()` in the DST console (`ctrl` + `` ` ``),
or by disconnecting and reconnecting. There is no need to fully restart the game. The console will also be extremely useful to modifying world/user states, so have a look at [the possible commands](https://dontstarve.fandom.com/wiki/Console/Don%27t_Starve_Together_Commands) if you haven't already.

---

To facilitate testing, you can install [No Mods Disabling](https://steamcommunity.com/sharedfiles/filedetails/?id=2161677657) to avoid having all your mods deselected whenever there's a bug.
You can also look at force enabling your mod via `dontstarve_steam.app/Contents/mods/modsettings.lua`.

---

For testing, you can use `print` in lua to output to the DST console.
For logs, you can look at your client logs, which are usually located under `Documents/Klei/DoNotStarveTogether/client_log.txt`.

## Mod Releasing

Install the DST Mod Tools:

* Click Steam > Library
* In you haven't already, click the `Games` dropdown on the top left and select `Tools`
* Search and install `Don't Starve Mod Tools`
* Launch and follow on screen instructions
