package Plugins::Daphile::PlayerSettings;

use strict;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Player::CapabilitiesHelper;

my $prefs = preferences('plugin.daphile');

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.daphile',
	    'defaultLevel' => 'WARN',
	    'description'  => getDisplayName(),
					   });

sub getDisplayName {
	return 'PLUGIN_DAPHILE';
}

sub needsClient {
	return 1;
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_DAPHILE');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/Daphile/settings/player.html');
}

# Defaults from the Daphile OS audio configuration (spac defaults.conf)
my %defaults = (
	resample        => 0,
	maxrate         => 192000,
	hdcd            => 0,
	deemph          => 0,
	rsqual          => 'v',
	rsphase         => 'M',
	rssteep         => 0,
	rsatt           => 1,
	pcm2dsd_rate    => 2822400,
	pcm2dsd_nsfilt  => 'sdm-4',
	dsd2dsd_cutoff  => 50,
	sdm_attenuate   => 7,
);

my @rates = (384000, 352800, 192000, 176400, 96000, 88200, 48000, 44100);

sub clamp {
	my ($v, $min, $max, $default) = @_;
	return $default unless defined $v && $v =~ /^\d+(\.\d+)?$/;
	return $min if $v < $min;
	return $max if $v > $max;
	return $v;
}

# Store the values that the Transcode helpers read with "playerpref plugin.daphile:<name> ?"
sub savePrefs {
	my ($client, $params) = @_;

	my $cprefs = $prefs->client($client);

	my $maxrate = $params->{'pref_maxrate'};
	$maxrate = $defaults{maxrate} unless grep { $_ eq ($maxrate || '') } @rates;

	my $qual  = ($params->{'pref_rsqual'}  || '') eq 'h' ? 'h' : 'v';
	my $phase = (grep { $_ eq ($params->{'pref_rsphase'} || '') } qw(L I M)) ? $params->{'pref_rsphase'} : 'M';
	my $steep = $params->{'pref_rssteep'} ? 1 : 0;
	my $att   = clamp($params->{'pref_rsatt'}, 0, 12, $defaults{rsatt});

	my $nsfilt = $params->{'pref_pcm2dsd_nsfilt'} || '';
	$nsfilt = $defaults{pcm2dsd_nsfilt} unless $nsfilt =~ /^(sdm|clans)-[45678]$/;

	my $dsdrate = $params->{'pref_pcm2dsd_rate'} || '';
	$dsdrate = $defaults{pcm2dsd_rate} unless grep { $_ eq $dsdrate } (2822400, 5644800, 11289600, 22579200);

	$cprefs->set('usedop', $params->{'pref_usedop'} ? 1 : 0);
	$cprefs->set('pcmdsf', $params->{'pref_pcmdsf'} ? 1 : 0);

	$cprefs->set('resample', $params->{'pref_resample'} ? 1 : 0);
	$cprefs->set('maxrate', $maxrate);
	$cprefs->set('rates', join(':', grep { $_ <= $maxrate } @rates));

	$cprefs->set('hdcd', $params->{'pref_hdcd'} ? 1 : 0);
	$cprefs->set('deemph', $params->{'pref_deemph'} ? 1 : 0);

	# "<quality><phase>[s]::<attenuation dB>" -> sox: rate -<quality><phase>[s]n <rate>
	$cprefs->set('rsqual', $qual);
	$cprefs->set('rsphase', $phase);
	$cprefs->set('rssteep', $steep);
	$cprefs->set('rsatt', $att);
	$cprefs->set('resample_setup', $qual . $phase . ($steep ? 's' : '') . '::' . $att);

	$cprefs->set('pcm2dsd_rate', $dsdrate);
	$cprefs->set('pcm2dsd_nsfilt', $nsfilt);
	$cprefs->set('dsd2dsd_cutoff', clamp($params->{'pref_dsd2dsd_cutoff'}, 20, 200, $defaults{dsd2dsd_cutoff}));
	$cprefs->set('sdm_attenuate', clamp($params->{'pref_sdm_attenuate'}, 6, 12, $defaults{sdm_attenuate}));
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ($params->{'saveSettings'}) {
		savePrefs($client, $params);
		Plugins::Daphile::Plugin::setupClient($client);
	}

	my %formats = map { $_ => 1 } Slim::Player::CapabilitiesHelper::supportedFormats($client);
	$params->{'dsf'} = $formats{'dsf'} ? 1 : 0;

	$params->{'daphile'} = ($client->model eq 'daphile') ? 1 : 0;

	my $playerip = $client->ip();
	if ($playerip eq '127.0.0.1') {
		$params->{'address'} = '';
	} else {
		$params->{'address'} = 'http://' . $playerip;
	}

	my $cprefs = $prefs->client($client);

	foreach my $pref ('usedop', 'pcmdsf', keys %defaults) {
		my $value = $cprefs->get($pref);
		$params->{'prefs'}->{$pref} = defined $value ? $value : ($defaults{$pref} || 0);
	}

	$params->{'rates'} = \@rates;

	return $class->SUPER::handler($client, $params);
}

sub getPrefs {
	return $prefs;
}

1;
