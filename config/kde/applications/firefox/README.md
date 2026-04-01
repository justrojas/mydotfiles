full-screen-api.ignore-widgets -> true
toolkit.legacyUserProfileCustomizations.stylesheets

- navigate to `Help` > `More Troubleshooting Information`
- click on `Open Directory`

Steps for applying this configuration

    Type about:profiles into your urlbar, accept the displayed warning.
    Open the root directory folder found on the page.
    Inside this folder, create a folder named "chrome".
    Add the userChrome.css file from this repo your new "chrome" folder.
    Type about:config into your urlbar and go to the page
    Paste "toolkit.legacyUserProfileCustomizations.stylesheets" into the search bar and set its value to true
    Restart Firefox.
    Done!
