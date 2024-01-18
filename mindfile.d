#!/usr/bin/env dub
/+ dub.sdl:
   name "mindfile"
   dependency "mind" version="~master"
   dependency "arsd-official:dom" version="~>10.9.2"
 +/
import arsd.dom : Document;
import mind : description, file, mindMain, sh, task, writeTimestamp;
import std.array : appender, join, split;
import std.datetime.stopwatch : AutoStart, StopWatch;
import std.file : SpanMode, dirEntries, exists, readText, write;
import std.format : format;
import std.process : environment;
import std.regex : matchFirst, regex;
import std.stdio : writeln;
import std.string : replace, rightJustify, startsWith;

enum counterRegexp = regex("counter-reset: h1 (\\d+)");

int createIndex(string baseDir, string relDir, string[] subPaths...)
{
    auto sw = StopWatch(AutoStart.yes);
    auto output = appender!string;
    output.reserve(10_000_000);
    output.put("CREATE TABLE IF NOT EXISTS searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);\n");
    output.put("CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);\n");
    foreach (subPathSpec; subPaths)
    {
        auto parts = subPathSpec.split("/");
        auto subpath = parts[0];
        auto type = parts[1];
        foreach (file; [baseDir, subpath].join("/").dirEntries("*", SpanMode.shallow))
        {
            writeln("Working on: ", file);
            auto text = file.readText;
            auto counter = text.matchFirst(counterRegexp);
            auto document = new Document(text);
            auto title = document.querySelector(".hyphenate>h1");
            if (title is null)
            {
                continue;
            }
            auto pageName = title.innerText.replace("'", "''");
            if (!counter.empty)
            {
                pageName = format!"%s - %s"(counter[1].rightJustify(2, '0'), pageName);
            }
            auto relPath = file[relDir.length+1..$];
            output.put("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('");
            output.put(pageName);
            output.put("', '");
            output.put(type);
            output.put("', '");
            output.put(relPath);
            output.put("');\n");
            foreach (element; document.querySelectorAll(".d_decl>div>span"))
            {
                auto anchor = element.getAttribute("id");
                if (anchor is null)
                {
                    continue;
                }
                if (!anchor.startsWith("."))
                {
                    continue;
                }
                auto name = anchor[1..$];
                output.put("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('");
                output.put(name);
                output.put("', 'Function', '");
                output.put(relPath);
                output.put("#");
                output.put(anchor);
                output.put("');\n");
            }
        }
    }
    "index.sql".write(output.data);
    writeln("Creation of index took: ", sw.peek);
    return 0;
}

auto home()
{
    return environment["HOME"];
}

int main(string[] args)
{
    description("all");
    auto all = task("all");

    description("Clean");
    task("clean", [],
         (t)
         {
             sh("rm -rf D.docset");
             sh("git restore D.docset");
         });

    description("Prepare");
    all.enhance(
      file("out/prepare-done", [],
           (t)
           {
               sh("mkdir -p out");
               sh("mkdir -p D.docset/Contents/Resources/Documents");
               sh(format!"cp -R %s/dlang/dmd-*/html/d/ D.docset/Contents/Resources/Documents"(home));
               t.name.writeTimestamp;
           }));

    enum SQLITE_DB = "D.docset/Contents/Resources/docSet.dsidx";
    description("Gen sqlite index");
    all.enhance(file(SQLITE_DB, ["out/prepare-done"],
         (t)
         {
             createIndex("D.docset/Contents/Resources/Documents", "D.docset/Contents/Resources/Documents", "phobos/Module", "spec/Section", "articles/Word",  "changelog/Tag");
             if (SQLITE_DB.exists)
             {
                 sh("rm %s".format(SQLITE_DB));
             }
             sh("sqlite3 %s < index.sql".format(t.name));
         }));

    description("Install");
    all.enhance(file("out/install-done", [SQLITE_DB],
        (t)
        {
            sh("cp -R D.docset \"%s/Library/Application Support/Zeal/Zeal/docsets/\"".format(home));
            t.name.writeTimestamp;
        }));

    return mindMain(args);
}
