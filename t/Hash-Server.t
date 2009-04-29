# ex: se ft=perl :
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Hash-Server.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
BEGIN { plan tests => 7 };
use Hash::Server ();
use Cache::Memcached ();
use Socket 'inet_ntoa';
ok(1); # If we made it this far, we're ok.

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $tries = 100;
my $ts;
my $port;
my $local_ip = do { inet_ntoa(scalar gethostbyname('localhost')) };

while (! $ts) {

	die 'Giving up on starting the test server!' if --$tries < 0;

	$port = int(rand 65535 - 49152) + 49152;

	$ts = Hash::Server->new({
			hash => {}, # silly
			localaddr => $local_ip,
			localport => $port,
			logfile => \*STDERR,
			pidfile => '/dev/null',
		});

	last if $ts;

}

warn "Trying to start server on $local_ip:$port now...\n";

$SIG{CHLD} = 'IGNORE';
my $pid = fork();

die if ! defined $pid;

if ($pid) {

	my $mc = Cache::Memcached->new({
			servers => [ "$local_ip:$port" ], debug => 1,
		});

	sleep 1;

	$mc->set('x', 12);
	ok($mc->get('x') == 12);

	$mc->incr('x');
	ok($mc->get('x') == 13);

	$mc->decr('x');
	ok($mc->get('x') == 12);

	$mc->delete('x');
	ok(! defined($mc->get('x')));

	$Hash::Server::UNDEFINED_KEY = q{};
	ok($mc->get('x') eq '');

	warn "Shutting down the server on $local_ip:$port...\n";

	kill 15, $pid;

	sleep 1;
	if (kill 0, $pid) {
		warn "Server is still alive! Trying kill -9...\n";
		sleep 1;
		kill 9, $pid;
		sleep 2;
		die "Still up! Giving up.\n" if kill(0, $pid);
	}

	ok(! defined($mc->get('x'))); # server is down

} else {
	$ts->Bind();
}
