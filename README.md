# EcoFlow Outage Widget

This Windows 11 tray widget helps engineers check backup power and plan remote workstation sessions around scheduled outages. It shows EcoFlow RIVER 2 Pro charge, wattage, estimated runtime, recent load, and the local outage schedule. The interactive web demo adds simulated CPU/GPU telemetry and AI usage budgets.

## Interactive demo

[Open the live demo](https://yourkeey.github.io/ecoflow-outage-widget/)

The browser demo follows the design and Russian labels of the Windows widget. Open **Настройки** (Settings) to switch between scheduled power, grid power, and an outage, change the workstation workload, or advance time by 15 minutes. Expand **Подробнее** (Details) for temperatures, charts, and AI usage budgets. Use **Отключения** (Outages) to compare today's and tomorrow's schedules.

Open `demo/index.html` in a browser. The demo runs entirely in the browser and requires no hardware, credentials, or backend.

<!-- Screenshot placeholder. Add docs/screenshot.png from the simulated dashboard. -->

## Architecture

| Component | Stack | Data and responsibilities |
| --- | --- | --- |
| Windows tray widget | Windows PowerShell 5.1, WPF/XAML, optional C# launcher | EcoFlow readings, 45-minute load history, outage countdowns, and Windows notifications |
| Desktop clients | PowerShell HTTPS and Python 3 standard library | EcoFlow developer API for readings, optional unofficial EcoFlow app API for supported station controls, and public CEK outage posts for queue 2.2 in Kyiv time |
| Web demo | HTML, CSS, JavaScript, Canvas | Local simulation for EcoFlow, outages, workstation telemetry, and AI limits |

The desktop widget keeps connection settings and history on the workstation. It can be viewed over an existing remote desktop connection. Live desktop integrations cover EcoFlow and CEK. PC telemetry and AI usage are simulated in the browser demo.

## Quick start on Windows

1. Install Python 3 and make sure `python.exe` is on `PATH` for outage updates and EcoFlow app-account mode.
2. From the project directory, launch the widget:

   ```powershell
   powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\widget.ps1
   ```

3. Use the connection dialog to select an EcoFlow region and enter your station serial plus either developer credentials or app-account credentials. Windows encrypts the saved password or secret key for the current user in `connection.xml`.

For file-based configuration, copy `.env.example` to `.env` and fill in the fields for `public` (developer API) or `private` (app account). Use a literal value after the first `=` on each line, without quotes. The widget loads a valid saved `connection.xml` first. Both `.env` and local data are excluded from Git. Prefer the Windows dialog for day-to-day use since `.env` stores values in plain text.

To build the optional launcher, run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-launcher.ps1`. Double-click the generated `EcoFlow Widget.exe` from the same directory as `widget.ps1`.

## Verification

```powershell
python -m unittest discover
Get-ChildItem -Filter 'test_*.ps1' | ForEach-Object {
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Failed: $($_.Name)" }
}
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\widget.ps1 -Check
node --test tests/demo.test.cjs
```

The desktop tests use local fixtures. The EcoFlow app API is unofficial and station control behavior depends on the device and firmware. The CEK reader handles text schedules; check the source publication for image-only updates.

## GitHub Pages

Push to a public repository with a `main` branch, select **Settings → Pages → Build and deployment → GitHub Actions**, and run **Deploy interactive demo** from the Actions tab. The workflow tests the simulation and publishes only the `demo/` directory. Find the live URL in the deployment job's `github-pages` environment. [GitHub Pages setup](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
