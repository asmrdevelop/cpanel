package Cpanel::Net::SSLeay::MultiDelimitReader;

# cpanel - Cpanel/Net/SSLeay/MultiDelimitReader.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# WARNING: This module will be rolled into Net::SSLeay or shipped as a separate
# CPAN module at some point in the future.  Please do not use this Cpanel namespace
# version in any 3rdparty code as it will be removed in future releases.

use strict;
use Net::SSLeay ();
use Errno       qw[EINTR];

# ssl_read_until_multi($ssl [, [$delimit,$delimit,...] [, $max_length]])
#  if $delimit missing, use $/ if it exists, otherwise use \n
#  read until delimiter reached, up to $max_length chars if defined
sub ssl_read_until_multi ($$;$) {
    use bytes;    # get rid of blength -- this is faster then having to call a separate sub and we can just
                  # use the CORE length function because it will now give us the correct length inside of
                  # this scope
    my (
        $ssl,         $delim, $max_length, $reply, $got, $this_delim_length, $max_delim_length, $pending,
        $peek_length, $found, $done,       $match, $err
    ) = ( $_[0], $_[1], $_[2] || 2000000000, '' );

    # According to RT ticket (https://rt.cpan.org/Public/Bug/Display.html?id=75045),
    # $[ was deprecated and started to give warnings in Perl version 5.12.0.
    # There is one instance of local $[; and there is no $[ assignement within scope.
    # Therefore, local $[; is removed.
    if ( $#$delim == 0 ) {
        $max_delim_length = length $delim->[0];
    }
    elsif ( $#$delim == 1 ) {
        $max_delim_length = length $delim->[0] > length $delim->[0] ? length $delim->[0] : length $delim->[1];
    }
    else {
        $max_delim_length = length( ( sort { length $b <=> length $a } @$delim )[0] );
    }
    while ( !$done && length($reply) < $max_length ) {

        #print STDERR "$$: [enter loop]\n";
        $!           = 0;
        $peek_length = length Net::SSLeay::peek( $ssl, 1 );    #Block if necessary until we get some data
        if ( !$peek_length ) {
            next if $! == EINTR;
            if ( $err = Net::SSLeay::ERR_get_error() ) { warn_known_errs( $err, 'SSL_peak' ); last; }
        }
        $pending = Net::SSLeay::pending($ssl) + length($reply);

        #print STDERR "$$: [pending] $pending\n";
        $peek_length = ( ( $pending > $max_length ) ? $max_length : $pending ) - length($reply);    #How much do we need to look for?
                                                                                                    #print STDERR "$$: [peek_length1] $peek_length\n";
        $peek_length = length( $got = Net::SSLeay::peek( $ssl, $peek_length ) );                    # how much did we get?
                                                                                                    #print STDERR "$$: [peek_length2] $peek_length\n";
                                                                                                    #print STDERR "$$: [got] [[$got]]\n";
        if ( ( !$peek_length || $peek_length < 0 ) && ( $err = Net::SSLeay::ERR_get_error() ) ) { warn_known_errs( $err, 'SSL_peak' ); last; }

        # the delimiter may be split across two gets, so we prepend
        # a little from the last get onto this one before we check
        # for a match
        if ( length($reply) >= $max_delim_length - 1 ) {

            #if what we've read so far is greater or equal
            #in length of what we need to prepatch
            $match = ( substr $reply, -1 * ( $max_delim_length + 1 ) ) . $got;
        }
        else {
            $match = $reply . $got;
        }

        #print STDERR "$$: [match] [[$match]]\n";

        foreach my $d (@$delim) {
            if ( ( $found = index( $match, $d ) ) > -1 ) {
                $this_delim_length = length $d;
                last;
            }
        }

        #print STDERR "$$: [this_delim_length] [[$this_delim_length]]\n";

        if ( $found > -1 ) {

            #print STDERR "$$: [found] $found\n";
            #print STDERR "$$: [length match] " . (length $match) . "\n";
            #print STDERR "$$: [length got] " . (length $got) . "\n";
            $reply .= $got = Net::SSLeay::read(
                $ssl,
                $found + $this_delim_length - ( ( length $match ) - ( length $got ) )
            );
            last;
        }
        else {
            $reply .= $got = Net::SSLeay::read( $ssl, $peek_length );
            last if ( $peek_length == $max_length - length($reply) );
        }

        #print STDERR "$$: [reply] [[$reply]]\n";
        if ( $err = Net::SSLeay::ERR_get_error() ) { warn_known_errs( $err, 'SSL_read' ); last; }
        Net::SSLeay::debug_read( \$reply, \$got ) if $Net::SSLeay::trace > 1;

        #print STDERR "$$: [got] [[$got]]\n";

        last if $got eq '';
    }
    return $reply;
}

sub warn_known_errs {
    my ( $err, $msg ) = @_;
    my ( $count, $errs, $e ) = ( 0, '' );
    while ( $err || ( $err = Net::SSLeay::ERR_get_error() ) ) {
        $count++;
        $e = "$msg $$: $count - " . Net::SSLeay::ERR_error_string($err) . "\n";
        $errs .= $e;
        warn $e if $Net::SSLeay::trace;
        $err = undef;
    }
    return $errs;
}

1;
__END__

package main;
use IO::Socket::SSL;
use Net::SSLeay;

my $socket = IO::Socket::SSL->new( PeerHost => 'koston.org', PeerPort => 2083, SSL_verify_mode => 0 );
print {$socket} "GET / HTTP/1.0\r\nHost: koston.org\r\n\r\n";
my $ssl  = $socket->_get_ssl_object();
my $data = Net::SSLeay::ssl_read_until_multi($ssl,["random","\r\n\r\n","\n\n"],1000000);
print $data;
