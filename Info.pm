package Plugins::Daphile::Info;

use strict;

use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.daphile');
my $log   = logger('plugin.daphile');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_DAPHILE_INFO');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/Daphile/settings/info.html');
}

sub prefs {
	return ($prefs);
}

# Directories to report free space for: the library, playlist and cache folders
sub infoPaths {
	my $server = preferences('server');
	my @dirs = grep { $_ && -d $_ } (
		$server->get('mediadirs') ? @{ $server->get('mediadirs') } : (),
		$server->get('playlistdir'),
		$server->get('cachedir'),
	);

	return join(':', @dirs);
}

# Run info.sh and return [ [label, value], ... ]
sub systemStatus {
	my $script = Slim::Utils::Misc::findbin('info.sh');

	if (!$script) {
		$log->warn('info.sh not found');
		return [];
	}

	local $ENV{DAPHILE_INFO_PATHS} = infoPaths();

	my @items;

	if (open(my $fh, '-|', $script)) {
		binmode($fh, ':utf8');

		while (my $line = <$fh>) {
			chomp $line;
			my ($label, $value) = split(/\t/, $line, 2);
			push @items, { label => $label, value => $value } if length $label;
		}

		close $fh;
	}
	else {
		$log->warn("Cannot run $script: $!");
	}

	return \@items;
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	$params->{'status'} = systemStatus();

	return $class->SUPER::handler($client, $params);
}

1;
