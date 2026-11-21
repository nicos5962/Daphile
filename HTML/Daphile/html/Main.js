Main = {
	background : Ext.get('background'),
	body : Ext.get(document.body),
	layout : null,

	init : function(){

		// overwrite some default Ext values
		Ext.UpdateManager.defaults.indicatorText = '<div class="loading-indicator">' + SqueezeJS.string('loading') + '</div>';
		SqueezeJS.UI.buttonTemplate = new Ext.Template(
			'<table border="0" cellpadding="0" cellspacing="0"><tbody><tr>',
			'<td></td><td><button type="{0}" style="padding:0" class="x-btn-text {2}"></button></td><td></td>',
			'</tr></tbody></table>'
		);
		SqueezeJS.UI.buttonTemplate.compile();

		SqueezeJS.UI.splitButtonTemplate = new Ext.Template(
			'<table id="{4}" cellspacing="0" class="x-btn {3}"><tbody class="{1}">',
			'<tr><td class="x-btn-ml"><i>&#160;</i></td><td class="x-btn-mc"><em class="{2}" unselectable="on"><button type="{0}"></button></em></td><td class="x-btn-mr"><i>&#160;</i></td></tr>',
			'</tbody></table>'
		);
		SqueezeJS.UI.splitButtonTemplate.compile();

		Ext.state.Manager.setProvider(new Ext.state.CookieProvider({
			expires: new Date(new Date().getTime()+(60*60*24*365*1000))
		}));

		SqueezeJS.setCookie('Squeezebox-enableHiDPI', window.devicePixelRatio);

		var leftpanel = {
			id: 'lpanel',
			region: 'center',
			layout: 'border',
			items: [
				{
					region: 'center',
					border: false,
					contentEl: 'leftcontent'
				}
			],
			border: false,
			margins: '0 0',
			split: true,
			minWidth: 354,
			width: '50%'
		};

		var rightpanel = {
			id: 'rpanel',
			region: 'east',
			layout: 'border',
			items: [
				{
					region: 'center',
					border: false,
					contentEl: 'rightcontent'
				}
			],
			border: false,
			margins: '0 0',
			split: true,
			collapsible: true,
			collapseMode: 'mini',
			minWidth: 354,
			listeners: {
				expand: function() {
					this.playlist.onResize();
					new Ext.util.DelayedTask(function(){ this.playlist.onResize(); }, this).delay(250);
				},
				scope: this
			},
			width: '50%',
			stateId: 'Squeezebox-panelWidth',
			stateful: true,
			header: false
		};

		var mainpanel = {
			layout: 'border',
			border: false,
			style: 'z-index: 200;',
			renderHidden: true,
			items: [
				{
					region: 'center',
					layout: 'border',
					border: false,
					margins: '4 4 0 4',
					items: [leftpanel, rightpanel]

				},

				{
					region: 'south',
					contentEl: 'footer',
					border: false,
					margins: '0 0 0 0',
					height: 34
				}
			]
		};

		this.layout = new Ext.Viewport(mainpanel);

		var el;
		if (el = Ext.get('scanWarning'))
			el.setVisibilityMode(Ext.Element.DISPLAY);

		if (el = Ext.get('newVersion'))
			el.setVisibilityMode(Ext.Element.DISPLAY);


		// initialize global controller, which is responsible for all communication with SC
		SqueezeJS.Controller.init({
			player: playerid
		});

		// initialize player control panel
		this.initPlayerControl();

		new SqueezeJS.UI.Buttons.PlayerDropdown({
			renderTo: 'playerChooser'
		});

		// initialize the playlist (right hand side) panel
		this._playlistInit();

		// initialize message area in footer
		this.showBrieflyArea = new SqueezeJS.UI.ShowBriefly({
			renderTo: 'footerInfoText',
			cls: 'showBrieflyArea',
			template: '{msg}'
		});


		// initialize scanner progress info in footer
		new SqueezeJS.UI.ScannerInfo({
			renderTo: 'scanWarning',
			name: 'progressName',
			info: 'progressInfo',
			done: 'progressDone',
			total: 'progressTotal'
		});

		// register event handler for left hand side frame: refresh when player is switched
		SqueezeJS.Controller.on({
			playerselected: {
				fn: this.onPlayerSelected
			}
		});

		Ext.EventManager.onWindowResize(this.onResize, this);
		this.onResize(window.innerWidth || document.documentElement.clientWidth, window.innerHeight || document.documentElement.clientHeight);

		// try { parent.setSBiFrameReady(); } catch(e) { }
		if (!SqueezeJS.cookiesEnabled())
			Ext.MessageBox.alert(SqueezeJS.string('squeezebox_server'), SqueezeJS.string('web_no_cookies_warning'));
	},

	onResize : function(width, height) {
		var el, newheight = height;

		Ext.util.CSS.updateRule('.x-menu-list', 'max-height', (height - 50) + 'px');

		if (touchOnlyDevice && ( el = Ext.getCmp("rpanel") ) ) {

			try {
				if (parent.document.body.className.indexOf("mobile") > -1)
					document.body.classList.add("mobile");
				else
					document.body.classList.remove("mobile");
			} catch(e) {
				if (screen.width < screen.height && screen.width < 720)
					document.body.classList.add("mobile");
				else
					document.body.classList.remove("mobile");
			}

			width -= 12; // margins and splitter
			var rw = Math.floor(width / 2);
			var lw = width - rw;

			el.setWidth(rw);

			if (document.getElementById("rpanel-xsplit").style.visibility != 'hidden') {
				Ext.getCmp("lpanel").setWidth(lw);
				Ext.get("rpanel").setLeft(4 + lw);
				Ext.get("rpanel-xsplit").setLeft(lw);
			}
		}

	},

	onPlayerSelected : function(playerobj) {
		if (playerobj && playerobj.playerid)
			playerobj = playerobj.playerid
		else
			playerobj = SqueezeJS.getPlayer();

		// set the browser frame to use the selected player
		if (frames.browser && frames.browser.location && frames.browser.location.protocol.match(/^http/)) {
			frames.browser.location = SqueezeJS.Utils.replacePlayerIDinUrl(frames.browser.location, playerobj);
		}

		// make the settings link use the new player ID
		var el;
		if (el = Ext.get('settingsHRef')) {
			el.dom.href = SqueezeJS.Utils.replacePlayerIDinUrl(el.dom.href, playerobj);
		}
		if (el = Ext.get('settingsBtn')) {
			el.dom.href = SqueezeJS.Utils.replacePlayerIDinUrl(el.dom.href, playerobj);
		}
	},

	initPlayerControl : function(){
		new SqueezeJS.UI.Buttons.Rew({
			renderTo: 'ctrlPrevious',
			noText:	  true,
			minWidth: 32
		});

		new SqueezeJS.UI.Buttons.Play({
			renderTo: 'ctrlTogglePlay',
			noText:	  true,
			minWidth: 32
		});

		new SqueezeJS.UI.Buttons.Fwd({
			renderTo: 'ctrlNext',
			noText:	  true,
			minWidth: 32
		});

		new SqueezeJS.UI.Buttons.Repeat({
			renderTo: 'ctrlRepeat',
			noText:	  true,
			minWidth: 32
		});

		new SqueezeJS.UI.Buttons.Shuffle({
			renderTo: 'ctrlShuffle',
			noText:	  true,
			minWidth: 32
		});

		new SqueezeJS.UI.Buttons.VolumeDown({
			renderTo: 'ctrlVolumeDown',
			noText:	  true,
			minWidth: 32
		});

		new SqueezeJS.UI.Buttons.VolumeUp({
			renderTo: 'ctrlVolumeUp',
			noText:	  true,
			minWidth: 32
		});

		new SqueezeJS.UI.VolumeBar({
			el: 'ctrlVolume',
			marginLeft: 7,
			marginRight: 6
		});

		new SqueezeJS.UI.Title('ctrlCurrentTitle');
		new SqueezeJS.UI.Album('ctrlCurrentAlbum');
		new SqueezeJS.UI.Contributors('ctrlCurrentArtist');
		new SqueezeJS.UI.Bitrate('ctrlBitrate');
		new SqueezeJS.UI.CurrentIndex('ctrlPlayNum');
		new SqueezeJS.UI.SongCount('ctrlSongCount');

		new SqueezeJS.UI.Playtime('ctrlPlaytime');
		new SqueezeJS.UI.PlaytimeRemaining('ctrlRemainingTime');
		new SqueezeJS.UI.PlaytimeProgress('ctrlProgress');

		new SqueezeJS.UI.Coverart({
			el: 'ctrlCurrentArt',
			size: 96
		});

		new SqueezeJS.UI.CoverartPopup({
			target: 'ctrlCurrentArt',
			defaultAlign: 'tl-bl'
		});

		// display song information with coverart in the collapsed mode
		new SqueezeJS.UI.CoverartPopup({
			target: 'nowPlayingIcon',
			defaultAlign: 'tl-bl',
			songInfo: true
		});

		var el;
		if (el = Ext.get('ctrlCurrentArt'))
			el.setVisibilityMode(Ext.Element.DISPLAY);

		if (el = Ext.get('expandedPlayerPanel'))
			el.setVisibilityMode(Ext.Element.DISPLAY);

	},

	_playlistInit : function(){
		this.playlist = new SqueezeJS.UI.Playlist({
			renderTo: 'playlistPanel',			// the panel where the playlist will be displayed
			playlistEl: 'playList',				// the actual playlist (the panel less the navigation bar, buttons etc.)
			currentSelector: 'div.currentSong'	// selector for the current playlist item
		});

		this.playlist.Highlighter = new SqueezeJS.UI.Highlight();

		this.playlist.onUpdated = function(o){
			var items = Ext.DomQuery.select('#' + this.playlistEl + ' div.draggableSong');
			if (items.length > 0) {
				if (Ext.get('btnPlaylistToggleArtwork')) {
					var noCover = SqueezeJS.getCookie('Squeezebox-noPlaylistCover') == '1';
					var menu = new Ext.menu.Menu({
						items: [
							new Ext.menu.CheckItem({
								text: SqueezeJS.string('hide_artwork'),
								cls: 'albumList',
								handler: function(){
									SqueezeJS.setCookie('Squeezebox-noPlaylistCover', 1);
									this.load();
								}.createDelegate(this),
								group: 'noCover',
								checked: noCover
							}),
							new Ext.menu.CheckItem({
								text: SqueezeJS.string('show_artwork'),
								cls: 'albumXList',
								handler: function(){
									SqueezeJS.setCookie('Squeezebox-noPlaylistCover', 0);
									this.load();
								}.createDelegate(this),
								group: 'noCover',
								checked: !noCover
							})
						]
					});

					new SqueezeJS.UI.SplitButton({
						renderTo: 'btnPlaylistToggleArtwork',
						icon: webroot + 'html/images/spacer.gif',
						cls: 'x-btn-icon album-list-' + (noCover ? '2' : '0'),
						menu: menu,
						arrowTooltip: SqueezeJS.string('coverart')
					});
				}

				new SqueezeJS.UI.Button({
					renderTo: 'btnPlaylistClear',
					cls:	  'btn-playlist-clear',
					tooltip:  SqueezeJS.string('clear_playlist'),
					minWidth: 32,
					noText:	  true,
					handler:  function(){
						SqueezeJS.Controller.playerControl(['playlist', 'clear']);
						this.load();							// Bug 5709: force playlist to clear
					}.createDelegate(this)
				});

				new SqueezeJS.UI.Button({
					renderTo: 'btnPlaylistSave',
					cls:	  'btn-playlist-save',
					tooltip:  SqueezeJS.string('save'),
					minWidth: 32,
					noText:	  true,
					handler:  function(){
						frames.browser.location = webroot + 'edit_playlist.html?player=' + SqueezeJS.Controller.getPlayer() + '&saveCurrentPlaylist=1';
					}
				});

				this.Highlighter.init({
					unHighlight : 'playList'
				});
			}
		};

	},

	collapseExpand : function(ev){
		var expandCookie = SqueezeJS.getCookie('Squeezebox-expandPlayerControl');
		expandCookie = expandCookie == 'false' ? false : true;

		var doExpand = ev.doExpand == null ? !expandCookie : ev.doExpand;

		var art = Ext.get('ctrlCurrentArt');

		// work around Safari 2 crasher: resize and hide artwork before hiding surrounding DIV
		if (art && !doExpand) {
			art.setHeight(0);
			art.hide();
		}

		var el;

		if (el = Ext.get('expandedPlayerPanel'))
			el.setVisible(doExpand);

		if (art && doExpand) {
			art.setHeight(96);
			art.show();
		}

		SqueezeJS.setCookie('Squeezebox-expandPlayerControl', doExpand);

		// resize the window if in undocked mode
		var el = Ext.get('ctrlUndock');
		if (el && !el.isVisible()) {
			var width = Ext.get(document.body).getWidth();
			var height = doExpand ? 200 : 115

			if (Ext.isOpera && doExpand) {
				height += 15;
			}

			window.resizeTo(width, height);
		}

		try { this.playlist.onResize(); }
		catch(e) {}
	}

};
