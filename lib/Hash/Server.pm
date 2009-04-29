package Hash::Server;
# ex: set ts=4 noexpandtab :
# $Id$

use 5.006;
use strict;
use integer;
use warnings;

(our $VERSION) = (q$Revision: 4114 $) =~ /(\d+)/g;

use base 'Net::Daemon';

our %CMD;
our $DEFAULT_FLAG = 0;
our $UNDEFINED_KEY;

sub Version ($) { join ' ', __PACKAGE__, $VERSION }

sub Run ($) {
	my $self = shift;

	my $sock = $self->{'socket'};
	my $line;

	LOOP: {
		unless (defined($line = $sock->getline)) {
			if ($sock->error) {
				$self->Error('Error %s', $sock->error);
			}
			$sock->close();
			return;
		}

		$line =~ s/[\r\n]+$//; # "chomp" CRLF
		(my $command, my @args) = split /\s/, $line;

		my $curhandle = select($sock);

		if ($CMD{$command}) {
			$CMD{$command}->($self, $sock, @args);
		}
		else {
			print "ERROR\r\n";
		}

		select($curhandle);

		redo LOOP;
	}
}

$CMD{get} = sub {
	my $self = shift;
	my $sock = shift;

	foreach my $key (@_) {
		my $r = $self->{hash}{$key};
		$r = $UNDEFINED_KEY if ! defined $r;

		if (defined $r) {
			printf "VALUE %s %d %d\r\n%s\r\n",
				$key, $DEFAULT_FLAG, length($r), $r;
		}
	}

	print "END\r\n";

};

$CMD{set} = sub {
	my($self, $sock, $key, $flags, $exptime, $bytes) = @_;
	# we ignore $flags and $exptime

	my $got = $sock->read(my $buf, $bytes);
	$self->{hash}{$key} = $buf;

	$got = $sock->read(undef, 2); # trailing \r\n

	print "STORED\r\n";
};

# same as set, but succeeds only if the server doesn't already hold data
# for this key
$CMD{add} = sub {
	my($self, $sock, $key, $flags, $exptime, $bytes) = @_;

	if (exists $self->{hash}{$key}) {
		print "NOT_STORED\r\n";
	}
	else {
		$CMD{set}->(@_);
	}
};

# same as set, but only succeeds if server DOES already hold data for this key
$CMD{replace} = sub {
	my($self, $sock, $key, $flags, $exptime, $bytes) = @_;

	if (exists $self->{hash}{$key}) {
		$CMD{set}->(@_);
	}
	else {
		print "NOT_STORED\r\n";
	}
};

$CMD{'delete'} = sub {
	my($self, $sock, $key) = @_; # ignoring optional 'time' arg

	my @n = delete($self->{hash}{$key});
	if (@n) {
		print "DELETED\r\n";
	}
	else {
		print "NOT_FOUND\r\n";
	}
};

$CMD{incr} = sub {
	my($self, $sock, $key, $delta) = @_;

	if ($delta =~ /^[\-]?\d+/) {
		my $n = ($self->{hash}{$key} += $delta);
		print "$n\r\n";
	}
	else {
		print "CLIENT_ERROR bad command line format\r\n";
		return;
	}
};

$CMD{decr} = sub {
	my $delta = pop @_;
	$CMD{incr}->(@_, $delta * -1);
};

1;
__END__

=head1 NAME

Hash::Server - A memcached-compatible interface to hashes

=head1 SYNOPSIS

	use Hash::Server ();
	use DB_File (); # for example

	tie(my %db, 'DB_File', './hash.db') or die $!;

	Hash::Server->new({ hash => \%db, localport => 11211 })->Bind();

=head1 DESCRIPTION

While memcached's original purpose was as a networked L<Memoize>,
it's also a simple way to distribute key/value hashes. But the
official memcached (as the name implies) stores its data in memory,
and is therefore temporary. Given there are so many memcached clients for
so many languages and platforms, it seemed a shame that there were no
other "backing stores" available.

This module allows you to distribute any Perl hash structure you like
with the memcached protocol. Typical use would probably involve a
tied hash (as in the L<DB_File> example above); if you want to serve
a straight untied hash, you might as well use the real memcached,
especially given the limitations of this module...

=head1 CAVEATS

This module's implementation of the memcached protocol is incomplete.

=over

=item *

It ignores any expiration times you provide; values are always assumed
permanent.

=item *

It ignores any incoming "flag" value you provide when storing,
and returns 0 by (default) when getting. Changing $Hash::Server::DEFAULT_FLAG
to another value may help you on the client-side to differentiate a
nonexistent key due to a server outage, or a nonexistent
key because the key just does not exist.

=item *

With standard memcached (flags field aside, which you can't get with the
Perl clients anyway), there is no way to tell the difference between a
nonexistent key and a down server. For pure caching, that's fine, but
your application may need to know the difference.
You can set $Hash::Server::UNDEFINED_KEY to some value that makes sense
to you, such as 0 or q{} (empty string) and test for that, knowing that
if your client returns 'undef', it means server down or server error.

=item *

The "stats" command is unimplemented.

=back

=head1 EXAMPLES

A DB_File server:

	use Hash::Server ();
	use DB_File ();

	$Hash::Server::UNDEFINED_KEY = q{};

	tie(my %db, 'DB_File', './hash.db') or die $!;

	Hash::Server->new({ hash => \%db, localport => 11211 })->Bind();


A client:

	use Cache::Memcached ();

	my $cache = Cache::Memcached->new({
			servers => [ '127.0.0.1:11211' ]
		});

	my $x = 'some string';
	$cache->set(string => $x);
	my $r = $cache->get('string');

	if (defined $r) {
		if (length $r) {
			if ($x eq $r) {
				print "'some string' is still '$x'\n";
			}
			else {
				print "'some string' is no longer '$x'; it's now '$r'\n";
			}
		}
		else {
			print "'some string' contains nothing: nonexistent\n";
		}
	}
	else {
		warn "Hash server is down!\n";
	}

=head1 SEE ALSO

L<Cache::Memcached>, L<Net::Daemon>, L<Cache::Memcached::XS>

http://code.sixapart.com/svn/memcached/trunk/server/doc/protocol.txt
http://dren.ch/perl-Hash-Server/

=head1 AUTHOR

Daniel Rench, E<lt>citric@cubicone.tmetic.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Daniel Rench

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.

=cut
