# Project home

Add the project home directory to your `config.ghostty` (open it with Ghostty's **Open Config** command):

```ghostty
macos-project-home-directory = /absolute/path/to/projects
macos-project-home-suffixes = -api,-admin,-admin-api
```

The directory setting is required to show the home icon. The suffixes are optional and default to `-api,-admin,-admin-api`. The home tab lists each immediate directory inside `macos-project-home-directory` as a group, then lists only matching child directories in that group. Search matches group and child directory names.

Select a child directory to open a new terminal tab with that directory as its working directory. The list refreshes on Ghostty configuration reload and each time the home icon is clicked. If the configured directory does not exist, the icon is hidden.
