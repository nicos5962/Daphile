function DaphileCssTheme(e) {
		var theme = 'default';
		var systemTheme = SqueezeJS.getCookie('DaphileWebThemeSystem');
		const darkModePreference = window.matchMedia("(prefers-color-scheme: dark)");

		if (systemTheme == 'true') {
		    if (window.matchMedia && darkModePreference.matches) {
						theme = 'default';
		    } else {
						theme = 'light';
		    }
		} else {
		    theme = SqueezeJS.getCookie('DaphileWebTheme');
		}
		if (theme != 'light') { theme = 'default'; }
		if (theme) { document.getElementById("theme").href="/Daphile/theme-" + theme + ".css"; }
		if (e=='init') {
				try {
						darkModePreference.addEventListener('change', DaphileCssTheme);
				} catch(error) {
						darkModePreference.addListener(DaphileCssTheme);
				}
		}
}

// Theme selector (from Daphile OS ThemeSelect): 'default' (dark), 'light' or 'system' (device)
function ThemeSelect(theme) {
		var systemTheme;
		var darkModePreference = window.matchMedia("(prefers-color-scheme: dark)");
		var sel = document.getElementById('theme_select');

		if (theme == 'init') {
				systemTheme = SqueezeJS.getCookie('DaphileWebThemeSystem');
				if (systemTheme == 'true') {
						theme = 'system';
				} else {
						systemTheme = 'false';
						theme = SqueezeJS.getCookie('DaphileWebTheme');
				}
				if (sel) { sel.value = (theme == 'light' || systemTheme == 'true') ? theme : 'default'; }
		}

		if (theme != 'light' && theme != 'system') { theme = 'default'; }
		if (theme == 'system') {
				systemTheme = 'true';
				theme = (window.matchMedia && darkModePreference.matches) ? 'default' : 'light';
		} else {
				systemTheme = 'false';
		}
		document.getElementById("theme").href = "/Daphile/theme-" + theme + ".css";
		// also update the frames of the main page (browse panel)
		for (var i = 0; i < window.frames.length; i++) {
				try {
						var t = window.frames[i].document.getElementById("theme");
						if (t) { t.href = "/Daphile/theme-" + theme + ".css"; }
				} catch (e) {}
		}
		var cookieExpiry = new Date;
		cookieExpiry.setFullYear(cookieExpiry.getFullYear() + 50);
		document.cookie = "DaphileWebTheme=" + theme + ";path=/;expires=" + cookieExpiry.toGMTString() + ';';
		document.cookie = "DaphileWebThemeSystem=" + systemTheme + ";path=/;expires=" + cookieExpiry.toGMTString() + ';';
}

// Wallpaper (from Daphile OS WallPaper): 'init' applies the saved state, 'toggle' flips it
function WallPaper(cmd) {
		var value = !(document.cookie.indexOf("DaphileWallPaper=false") > -1);

		if (cmd == 'toggle') value = !value;

		if (value) {
				document.body.classList.add('wallpaper');
		} else {
				document.body.classList.remove('wallpaper');
		}

		var cookieExpiry = new Date;
		cookieExpiry.setFullYear(cookieExpiry.getFullYear() + 50);
		document.cookie = "DaphileWallPaper=" + value + ";path=/;expires=" + cookieExpiry.toGMTString() + ';';
}
