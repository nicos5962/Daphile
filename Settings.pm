package Plugins::Daphile::Settings;

use strict;

use base qw(Slim::Web::Settings);

use File::Spec::Functions qw(catfile);
use HTTP::Status qw(RC_NOT_FOUND);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.daphile');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_DAPHILE');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/Daphile/settings/basic.html');
}

sub prefs {
	return ($prefs, 'overrideTranscoding');
}

# Player logs written by the Daphile helpers: <log dir>/daphile/remote_players/<mac>/transcode.log
sub playerLogs {
	my %logs;

	foreach my $file (glob(catfile(Plugins::Daphile::Plugin::logDir(), '*', 'transcode.log'))) {
		my ($mac) = $file =~ m{/([^/]+)/transcode\.log$};
		$logs{$mac} = $file if $mac;
	}

	return \%logs;
}

# Same as the OS: Media Server logs and one entry per player
sub logList {
	my $client_name = sub {
		my $mac = shift;
		my $client = Slim::Player::Client::getClient(lc $mac);
		return $client ? $client->name : $mac;
	};

	my @list = (
		{ label => 'Media Server log', url => 'server.log' },
		{ label => 'Media Scanner log', url => 'scanner.log' },
	);

	my $logs = playerLogs();

	foreach my $mac (sort keys %$logs) {
		push @list, {
			label => 'Transcode log: ' . $client_name->($mac),
			url   => 'plugins/Daphile/log.html?mac=' . $mac,
		};
	}

	return \@list;
}

# Player log page: uses the core log viewer (refresh, search, line count, download)
sub logHandler {
	my ($client, $params, undef, $httpClient, $response) = @_;

	my $logFile = playerLogs()->{ $params->{mac} || '' };

	return Slim::Web::Pages::Common->logFileViewer($client, $params, $httpClient, $response, $logFile)
		if $logFile;

	$response->code(RC_NOT_FOUND);
	return 'Log not found';
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	$params->{'logs'} = logList();

	return $class->SUPER::handler($client, $params);
}

1;
