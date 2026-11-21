package Plugins::Daphile::Plugin;

use strict;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::TranscodingHelper;
use Slim::Player::CapabilitiesHelper;

use Plugins::Daphile::PlayerSettings;
use Plugins::Daphile::Settings;
use Plugins::Daphile::Info;

use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile);
use Slim::Utils::OSDetect;

my $log = logger('plugin.daphile');

my $prefs = preferences('plugin.daphile');

$prefs->init({ overrideTranscoding => 0 });

# Parse a convert.conf style file into the transcoding tables (same format
# as Slim::Player::TranscodingHelper::loadConversionTables).
sub loadConvertFile {
	my $file = shift;

	open(my $fh, '<', $file) || return $log->warn("Cannot read $file: $!");

	while (my $line = <$fh>) {
		next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
		$line =~ s/#.*$//; $line =~ s/^\s+|\s+$//g;

		next unless $line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$/;
		my $profile = "$1-$2-$3-" . lc($4);

		if ($Slim::Player::TranscodingHelper::commandTable{$profile}) {
			my @index = sort grep { $_ =~ /\Q$profile\E/ } keys %Slim::Player::TranscodingHelper::commandTable;
			$profile .= '-' . (($index[-1] =~ /-(\d+$)/)[0] + 1);
		}

		$line = <$fh>;
		if ($line =~ /^\s+#\s+(\S.*)/) {
			Slim::Player::TranscodingHelper::_getCapabilities($profile, $1);
			$line = <$fh>;
		} else {
			$Slim::Player::TranscodingHelper::capabilities{$profile} = {I => 'noArgs', F => 'noArgs'};
		}

		my $command = $line;
		$command =~ s/^\s+|\s+$//g if defined $command;
		next unless defined $command && length $command;
		$Slim::Player::TranscodingHelper::commandTable{$profile} = $command;
	}
	close $fh;
}


sub deleteDefaultRule{
	my $prefix = shift;

	my $profile =  $prefix . '-*-*';
	my @index = sort grep { $_ =~ /\Q$profile\E/ } keys %Slim::Player::TranscodingHelper::commandTable;
	$profile = $index[-1] || return;

	main::INFOLOG && $log->info("Remove the top level convert.conf rule: $profile");
	delete $Slim::Player::TranscodingHelper::capabilities{$profile};
	delete $Slim::Player::TranscodingHelper::commandTable{$profile};
}

sub confFile {
	return catfile(dirname(__FILE__), 'daphile-convert.conf');
}

# Where the Transcode/Decode/... helpers write <mac>/transcode.log
sub logDir {
	return File::Spec::Functions::catdir(scalar Slim::Utils::OSDetect::dirsFor('log'), 'daphile', 'remote_players');
}

# Environment inherited by the Transcode/Decode/... helpers spawned by LMS
sub setHelperEnv {
	my $port = preferences('server')->get('httpport') || 9000;
	$ENV{LMS_JSONRPC} = "http://127.0.0.1:$port/jsonrpc.js";
	$ENV{DAPHILE_LOGDIR} = logDir();
}

# Replace the stock convert.conf rules with the Daphile ones
sub applyOverride {
	setHelperEnv();
	main::INFOLOG && $log->info("Initialize Daphile specific transcoding rules.");

	foreach my $oldrule
	    (
	     'aac-aac','aac-flc','aac-mp3','aac-pcm',
	     'aif-aif','aif-flc','aif-mp3','aif-pcm',
	     'alc-alc','alc-flc','alc-mp3','alc-pcm',
	     'alcx-flc','alcx-mp3','alcx-pcm',
	     'ape-flc','ape-mp3','ape-pcm','ape-wav',
	     'dff-dff',
	     'dsf-dsf',
	     'flc-aif','flc-flc','flc-mp3','flc-pcm',
	     'mp3-mp3',
	     'mp4-aac','mp4-flc','mp4-mp3','mp4-pcm',
	     'mp4x-flc','mp4x-mp3','mp4x-pcm',
	     'mpc-aif','mpc-flc','mpc-mp3','mpc-pcm',
	     'ogf-flc','ogf-ogf',
	     'ogg-aif','ogg-flc','ogg-mp3','ogg-ogg','ogg-pcm',
	     'ops-aif','ops-flc','ops-mp3','ops-ops','ops-pcm',
	     'shn-flc','shn-mp3','shn-pcm','shn-wav',
	     'sls-flc','sls-mp3','sls-pcm',
	     'tak-flc','tak-mp3','tak-pcm','tak-wav',
	     'tta-flc','tta-mp3','tta-pcm','tta-wav',
	     'wav-flc','wav-mp3','wav-pcm','wav-wav',
	     'wma-flc','wma-mp3','wma-pcm','wma-wma',
	     'wmal-flc','wmal-mp3','wmal-pcm','wmal-wmal',
	     'wmap-flc','wmap-mp3','wmap-pcm','wmap-wmap',
	     'wvp-flc','wvp-mp3','wvp-pcm',
	     'wvpx-dff','wvpx-dsf','wvpx-flc'
	    ) {
		    deleteDefaultRule($oldrule);
	}

	loadConvertFile(confFile());

	if (Slim::Utils::PluginManager->isEnabled('Plugins::Spotty::Plugin')) {
		my $helper = Plugins::Spotty::Helper->get();
		$helper =~ s/.*\///;

		my $rule = 'spt-wav-daphile-*';
		main::INFOLOG && $log->info("Setting up rule: $rule");
		$Slim::Player::TranscodingHelper::capabilities{$rule} = {R => 'PATH=%F', T => 'START=--start-position %s'};
		$Slim::Player::TranscodingHelper::commandTable{$rule} = '[' . $helper . '] -n Squeezebox -c "$CACHE$" --single-track $PATH$ --disable-discovery --disable-audio-cache $START$' . '| [Transcode] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f wav -';

		$rule = 'spt-flc-daphile-*';
		main::INFOLOG && $log->info("Setting up rule: $rule");
		$Slim::Player::TranscodingHelper::capabilities{$rule} = {R => 'PATH=%F', T => 'START=--start-position %s'};
		$Slim::Player::TranscodingHelper::commandTable{$rule} = '[' . $helper . '] -n Squeezebox -c "$CACHE$" --single-track $PATH$ --disable-discovery --disable-audio-cache $START$' . '| [Transcode] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f flac -';
	}

	if (Slim::Utils::PluginManager->isEnabled('Plugins::CDplayer::Plugin')) {
		my $rule = 'cdplay-flc-*-*';
		main::INFOLOG && $log->info("Setting up rule: $rule");
		$Slim::Player::TranscodingHelper::capabilities{$rule} = {R => 'PATH=%F'};
		$Slim::Player::TranscodingHelper::commandTable{$rule} = '[cdda2wav] --speed $CDSPEED$ --output-format wav -gui output-endianess=little --quiet device=$CDDEVICE$ -track $CDTRACK$ $CDOFFSET$ - '
		    . '| [Transcode] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f flc pipe:';

		$rule = 'cdplay-mp3-*-*';
		main::INFOLOG && $log->info("Setting up rule: $rule");
		$Slim::Player::TranscodingHelper::capabilities{$rule} = {R => 'PATH=%F', D => 'RESAMPLE=-r %d', B=> 'BITRATE=-B %B'};
		$Slim::Player::TranscodingHelper::commandTable{$rule} = '[cdda2wav] --speed $CDSPEED$ --output-format wav -gui output-endianess=little --quiet device=$CDDEVICE$ -track $CDTRACK$ $CDOFFSET$ - '
		    . '| [Transcode] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f mp3 $RESAMPLE$ $BITRATE$ -q $QUALITY$ pipe:';

		$rule = 'cdplay-pcm-*-*';
		main::INFOLOG && $log->info("Setting up rule: $rule");
		$Slim::Player::TranscodingHelper::capabilities{$rule} = {R => 'PATH=%F'};
		$Slim::Player::TranscodingHelper::commandTable{$rule} = '[cdda2wav] --speed $CDSPEED$ --output-format wav -gui output-endianess=little --quiet device=$CDDEVICE$ -track $CDTRACK$ $CDOFFSET$ - '
		    . '| [Transcode] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f pcm pipe:';

		$rule = 'cdplay-wav-daphile-*';
		$Slim::Player::TranscodingHelper::capabilities{$rule} = {R => 'PATH=%F'};
		$Slim::Player::TranscodingHelper::commandTable{$rule} = '[cdda2wav] --speed $CDSPEED$ --output-format wav -gui output-endianess=little --quiet device=$CDDEVICE$ -track $CDTRACK$ $CDOFFSET$ - '
		    . '| [Decode] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f wav pipe:';
	}

	preferences('server')->set('isDaphile', 1);

	foreach my $client (Slim::Player::Client::clients()) {
		setupClient($client);
	}
}

# Back to the stock rules: drop everything and reload the conversion tables
sub removeOverride {
	main::INFOLOG && $log->info('Restoring stock transcoding rules.');

	%Slim::Player::TranscodingHelper::commandTable = ();
	%Slim::Player::TranscodingHelper::capabilities = ();
	%Slim::Player::TranscodingHelper::binaries     = ();
	Slim::Player::TranscodingHelper::loadConversionTables();

	preferences('server')->remove('isDaphile');
}

sub initPlugin {
	my $class = shift;

	Plugins::Daphile::Settings->new;
	Plugins::Daphile::Info->new;

	Slim::Web::Pages->addPageFunction('plugins/Daphile/log.html', \&Plugins::Daphile::Settings::logHandler);
	Plugins::Daphile::PlayerSettings->new;

	Slim::Control::Request::subscribe(\&setupTranscoder, [['prefset','plugin.daphile']]);
	Slim::Control::Request::subscribe(\&initClient, [['client'],['new','reconnect']]);

	# toggled from the settings page: apply immediately, no restart needed
	$prefs->setChange(sub {
		$_[1] ? applyOverride() : removeOverride();
	}, 'overrideTranscoding');

	if ($prefs->get('overrideTranscoding')) {
		applyOverride();
	} else {
		main::INFOLOG && $log->info('Daphile transcoding override disabled (pref overrideTranscoding).');
	}
}

sub setupTranscoder {
	my $request = shift;

	my $client = $request->client() || return;
	my $mac = lc($client->macaddress);

	main::INFOLOG && $log->info("Transcoder setup for player: $mac");
	setupClient($client);
}

sub setupClient {
	my $client = $_[0] || return;
	return unless $prefs->get('overrideTranscoding');
	my $mac = lc($client->macaddress);
	my $usedop = $prefs->client($client)->get('usedop');
	my $pcmdsf = $prefs->client($client)->get('pcmdsf');

	main::INFOLOG && $log->info("Player $mac usedop: $usedop");
	main::INFOLOG && $log->info("Player $mac pcmdsf: $pcmdsf");

	my $dsf = 'dsf-wav-daphile-' . $mac;
	my $dff = 'dff-wav-daphile-' . $mac;
	if ($client->model eq 'daphile') {
		if ($usedop) {
			main::INFOLOG && $log->info("Setting up rule: $dsf");
			$Slim::Player::TranscodingHelper::capabilities{$dsf} = {F => 'PATH=%f', I => 'PATH=-', R => 'PATH=%F', T => 'START=-s %s', U => 'END=-d %w', D => 'RESAMPLE=-r %d'};
			$Slim::Player::TranscodingHelper::commandTable{$dsf} = '[DoP-encode] -F ' . $dsf . ' -m $CLIENTID$ -p $PLAYER$ -x -f wav $START$ $END$ $RESAMPLE$ $PATH$';
			main::INFOLOG && $log->info("Setting up rule: $dff");
			$Slim::Player::TranscodingHelper::capabilities{$dff} = {F => 'PATH=%f', I => 'PATH=-', R => 'PATH=%F', T => 'START=-s %s', U => 'END=-d %w', D => 'RESAMPLE=-r %d'};
			$Slim::Player::TranscodingHelper::commandTable{$dff} = '[DoP-encode] -F ' . $dff . ' -m $CLIENTID$ -p $PLAYER$ -x -f wav $START$ $END$ $RESAMPLE$ $PATH$';
		} else {
			main::INFOLOG && $log->info("Deleting rule: $dsf");
			delete $Slim::Player::TranscodingHelper::capabilities{$dsf};
			delete $Slim::Player::TranscodingHelper::commandTable{$dsf};
			main::INFOLOG && $log->info("Deleting rule: $dff");
			delete $Slim::Player::TranscodingHelper::capabilities{$dff};
			delete $Slim::Player::TranscodingHelper::commandTable{$dff};
		}
	}

	$dsf = 'dsf-flc-*-' . $mac;
	$dff = 'dff-flc-*-' . $mac;
	if ($usedop) {
		main::INFOLOG && $log->info("Setting up rule: $dsf");
		$Slim::Player::TranscodingHelper::capabilities{$dsf} = {F => 'PATH=%f', I => 'PATH=-', R => 'PATH=%F', T => 'START=-s %s', U => 'END=-d %w', D => 'RESAMPLE=-r %d'};
		$Slim::Player::TranscodingHelper::commandTable{$dsf} = '[DoP-encode] -F ' . $dsf . ' -m $CLIENTID$ -p $PLAYER$ -x -f flac $START$ $END$ $RESAMPLE$ $PATH$';
		main::INFOLOG && $log->info("Setting up rule: $dff");
		$Slim::Player::TranscodingHelper::capabilities{$dff} = {F => 'PATH=%f', I => 'PATH=-', R => 'PATH=%F', T => 'START=-s %s', U => 'END=-d %w', D => 'RESAMPLE=-r %d'};
		$Slim::Player::TranscodingHelper::commandTable{$dff} = '[DoP-encode] -F ' . $dff . ' -m $CLIENTID$ -p $PLAYER$ -x -f flac $START$ $END$ $RESAMPLE$ $PATH$';
	} else {
		main::INFOLOG && $log->info("Deleting rule: $dsf");
		delete $Slim::Player::TranscodingHelper::capabilities{$dsf};
		delete $Slim::Player::TranscodingHelper::commandTable{$dsf};
		main::INFOLOG && $log->info("Deleting rule: $dsf");
		delete $Slim::Player::TranscodingHelper::capabilities{$dff};
		delete $Slim::Player::TranscodingHelper::commandTable{$dff};
	}

	my @srcfmts = ( 'aac', 'aif', 'alc', 'alcx', 'ape', 'flc', 'mp3', 'mp4', 'mp4x', 'mpc', 'ogg', 'ogf', 'ops', 'shn', 'tak', 'tta', 'wav', 'wma', 'wmal', 'wmap' );
	my @stdin_fmts = ( 'aac', 'flc', 'mp3', 'mpc', 'ogg', 'ogf', 'ops' );

	foreach my $srcfmt (@srcfmts) {
		my $rule = $srcfmt . '-dff-*-' . $mac;
		if ($pcmdsf) {
			if ($srcfmt ~~ @stdin_fmts) {
				$Slim::Player::TranscodingHelper::capabilities{$rule} = {F => 'PATH=%f', I => 'PATH=-', R => 'PATH=%F', T => 'START=-s %s', U => 'END=-d %w', D => 'RESAMPLE=-r %d'};
			} else {
				$Slim::Player::TranscodingHelper::capabilities{$rule} = {F => 'PATH=%f', R => 'PATH=%F', T => 'START=-s %s', U => 'END=-d %w', D => 'RESAMPLE=-r %d'};
			}
			$Slim::Player::TranscodingHelper::commandTable{$rule} = '[Transcode] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f dff $START$ $END$ $RESAMPLE$ $PATH$';
		} else {
			delete $Slim::Player::TranscodingHelper::capabilities{$rule};
			delete $Slim::Player::TranscodingHelper::commandTable{$rule};
		}
	}

	if (Slim::Utils::PluginManager->isEnabled('Plugins::Spotty::Plugin')) {
		my $helper = Plugins::Spotty::Helper->get();
		$helper =~ s/.*\///;

		my $rule = 'spt-dff-*-' . $mac;
		if ($pcmdsf) {
			main::INFOLOG && $log->info("Setting up rule: $rule");
			$Slim::Player::TranscodingHelper::capabilities{$rule} = {R => 'PATH=%F', T => 'START=--start-position %s'};
			$Slim::Player::TranscodingHelper::commandTable{$rule} = '[' . $helper . '] -n Squeezebox -c "$CACHE$" --single-track $PATH$ --disable-discovery --disable-audio-cache $START$'
		    . '| [Transcode] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f dff -';
		} else {
			main::INFOLOG && $log->info("Deleting rule: $rule");
			delete $Slim::Player::TranscodingHelper::capabilities{$rule};
			delete $Slim::Player::TranscodingHelper::commandTable{$rule};
		}

		$rule = 'spt-dsf-*-' . $mac;
		if ($pcmdsf) {
			main::INFOLOG && $log->info("Setting up rule: $rule");
			$Slim::Player::TranscodingHelper::capabilities{$rule} = {R => 'PATH=%F', T => 'START=--start-position %s'};
			$Slim::Player::TranscodingHelper::commandTable{$rule} = '[' . $helper . '] -n Squeezebox -c "$CACHE$" --single-track $PATH$ --disable-discovery --disable-audio-cache $START$'
			    . '| [Transcode] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f dsf -';
		} else {
			main::INFOLOG && $log->info("Deleting rule: $rule");
			delete $Slim::Player::TranscodingHelper::capabilities{$rule};
			delete $Slim::Player::TranscodingHelper::commandTable{$rule};
		}
	}

	if (Slim::Utils::PluginManager->isEnabled('Plugins::CDplayer::Plugin')) {
		my $rule = 'cdplay-dff-*-' . $mac;
		if ($pcmdsf) {
			main::INFOLOG && $log->info("Setting up rule: $rule");
			$Slim::Player::TranscodingHelper::capabilities{$rule} = {R => 'PATH=%F'};
			$Slim::Player::TranscodingHelper::commandTable{$rule} = '[cdda2wav] --speed $CDSPEED$ --output-format wav -gui output-endianess=little --quiet device=$CDDEVICE$ -track $CDTRACK$ $CDOFFSET$ - '
			    . '| [Transcode] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f dff pipe:';
		} else {
			main::INFOLOG && $log->info("Deleting rule: $rule");
			delete $Slim::Player::TranscodingHelper::capabilities{$rule};
			delete $Slim::Player::TranscodingHelper::commandTable{$rule};
		}

		$rule = 'cdplay-dsf-*-' . $mac;
		if ($pcmdsf) {
			main::INFOLOG && $log->info("Setting up rule: $rule");
			$Slim::Player::TranscodingHelper::capabilities{$rule} = {R => 'PATH=%F'};
			$Slim::Player::TranscodingHelper::commandTable{$rule} = '[cdda2wav] --speed $CDSPEED$ --output-format wav -gui output-endianess=little --quiet device=$CDDEVICE$ -track $CDTRACK$ $CDOFFSET$ - '
			    . '| [Transcode] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f dsf pipe:';
		} else {
			main::INFOLOG && $log->info("Deleting rule: $rule");
			delete $Slim::Player::TranscodingHelper::capabilities{$rule};
			delete $Slim::Player::TranscodingHelper::commandTable{$rule};
		}
	}

	$dsf = 'dsf-dsf-*-' . $mac;
	$dff = 'dff-dff-*-' . $mac;
	if ($client->model eq 'daphile' && $pcmdsf) {
		main::INFOLOG && $log->info("Setting up rule: $dsf");
		$Slim::Player::TranscodingHelper::capabilities{$dsf} = {F => 'PATH=%f', I => 'PATH=-', R => 'PATH=%F', T => 'START=-s %s', U => 'END=-d %w', D => 'RESAMPLE=-r %d'};
		$Slim::Player::TranscodingHelper::commandTable{$dsf} = '[Native+] -F ' . $dsf . ' -m $CLIENTID$ -p $PLAYER$ -f dsf $START$ $END$ $RESAMPLE$ $PATH$';
		main::INFOLOG && $log->info("Setting up rule: $dff");
		$Slim::Player::TranscodingHelper::capabilities{$dff} = {F => 'PATH=%f', I => 'PATH=-', R => 'PATH=%F', T => 'START=-s %s', U => 'END=-d %w', D => 'RESAMPLE=-r %d'};
		$Slim::Player::TranscodingHelper::commandTable{$dff} = '[Native+] -F ' . $dff . ' -m $CLIENTID$ -p $PLAYER$ -f dff $START$ $END$ $RESAMPLE$ $PATH$';
	} else {
		main::INFOLOG && $log->info("Deleting rule: $dsf");
		delete $Slim::Player::TranscodingHelper::capabilities{$dsf};
		delete $Slim::Player::TranscodingHelper::commandTable{$dsf};
		main::INFOLOG && $log->info("Deleting rule: $dff");
		delete $Slim::Player::TranscodingHelper::capabilities{$dff};
		delete $Slim::Player::TranscodingHelper::commandTable{$dff};
	}

	if ($client->model eq 'daphile') {
		my $ntvplus = $prefs->client($client)->get('ntvplus');
		main::INFOLOG && $log->info("Player $mac ntvplus: $ntvplus");
		my $rule = 'flc-flc-daphile-' . $mac;
		if ($ntvplus) {
			main::INFOLOG && $log->info("Setting up rule: $rule");
			$Slim::Player::TranscodingHelper::capabilities{$rule} = {F => 'PATH=%f', I => 'PATH=-', R => 'PATH=%F', T => 'START=-s %s', U => 'END=-d %w', D => 'RESAMPLE=-r %d'};
			$Slim::Player::TranscodingHelper::commandTable{$rule} = '[Native+] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f flac $START$ $END$ $RESAMPLE$ $PATH$';
		} else {
			main::INFOLOG && $log->info("Deleting rule: $rule");
			delete $Slim::Player::TranscodingHelper::capabilities{$rule};
			delete $Slim::Player::TranscodingHelper::commandTable{$rule};
		}

		$rule = 'aif-aif-daphile-' . $mac;
		if ($ntvplus) {
			main::INFOLOG && $log->info("Setting up rule: $rule");
			$Slim::Player::TranscodingHelper::capabilities{$rule} = {F => 'PATH=%f', R => 'PATH=%F', T => 'START=-s %s', U => 'END=-d %w', D => 'RESAMPLE=-r %d'};
			$Slim::Player::TranscodingHelper::commandTable{$rule} = '[Native+] -F ' . $rule . ' -m $CLIENTID$ -p $PLAYER$ -f aiff $START$ $END$ $RESAMPLE$ $PATH$';
		} else {
			main::INFOLOG && $log->info("Deleting rule: $rule");
			delete $Slim::Player::TranscodingHelper::capabilities{$rule};
			delete $Slim::Player::TranscodingHelper::commandTable{$rule};
		}
	}

}

sub initClient {
	my $request = shift;
	my $client = $request->client() || return;
	my $mac = lc($client->macaddress);
	main::INFOLOG && $log->info("Initialize player: $mac");

	$prefs->client($client)->set('formats', join(':',Slim::Player::CapabilitiesHelper::supportedFormats($client)));

	setupClient($client)
}

1;
