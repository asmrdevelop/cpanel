package Whostmgr::Resolvers;

# cpanel - Whostmgr/Resolvers.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Sys::Hostname    ();
use Cpanel::SafeFile         ();
use Cpanel::StringFunc::Trim ();
use Cpanel::Validate::IP     ();

sub _get_resolv_conf_file {
    return '/etc/resolv.conf';
}

sub setupresolvers {
    my (@nameservers) = @_;

    my $gotns = 0;

    # TODO: check to see if resolvers actually work
    # TODO: verify lookup of cpanel.net and reset resolv.conf upon failure
    my @RESOLVERS;
    foreach my $ns (@nameservers) {
        chomp $ns;
        Cpanel::StringFunc::Trim::ws_trim( \$ns );
        if ( Cpanel::Validate::IP::is_valid_ip($ns) ) {
            $gotns++;
            push @RESOLVERS, $ns;
        }
    }

    if ( $gotns < 1 ) {
        return ( 0, 'You did not specify any valid resolvers.' );
    }

    my $mode = '>';
    $mode = '+<'
      if -e _get_resolv_conf_file();

    my $resolvlck = Cpanel::SafeFile::safeopen( \*RESOLV, $mode, _get_resolv_conf_file() );
    if ( !$resolvlck ) {
        return ( 0, 'Could not open ' . _get_resolv_conf_file() . ": $!" );
    }
    my @RESOLV;
    if ( $mode eq '+<' ) {
        @RESOLV = <RESOLV>;
        seek( RESOLV, 0, 0 );
    }

    my $is_cpanel_system = 0;
    my $hostname         = Cpanel::Sys::Hostname::gethostname();
    if ( $hostname =~ m/\.?(?:darkorb\.net|cpanel\.net)$/i ) {
        $is_cpanel_system = 1;
    }

    my @SEARCHSERVERS;
    my @SEARCH = grep( /^\s*search\s+/, @RESOLV );
    foreach my $searchline (@SEARCH) {
        $searchline =~ s/\;.*$//;    # Trim possible EOL comments
        chomp $searchline;
        Cpanel::StringFunc::Trim::ws_trim( \$searchline );
        foreach my $server ( split( /\s+/, ( split( /\s+/, $searchline, 2 ) )[1] ) ) {
            next if ( $server eq 'search' || ( !$is_cpanel_system && $server =~ m/^(?:darkorb\.net|cpanel\.net)$/i ) );
            if ( !grep( /^\Q$server\E$/, @SEARCHSERVERS ) ) {
                push @SEARCHSERVERS, $server;
            }
        }
    }

    if (@SEARCHSERVERS) {
        print RESOLV 'search ' . join( ' ', @SEARCHSERVERS ) . "\n";
    }
    foreach my $line (@RESOLV) {
        next if $line =~ m/^search\s+/i;
        next if $line =~ m/^nameserver/;
        next if ( !$is_cpanel_system && $line =~ m/^domain\s+(?:darkorb\.net|cpanel\.net)/i );
        print RESOLV $line;
    }
    foreach my $nameserver (@RESOLVERS) {
        print RESOLV "nameserver $nameserver\n";
    }
    truncate( RESOLV, tell(RESOLV) );
    Cpanel::SafeFile::safeclose( \*RESOLV, $resolvlck );

    my @output = ( 1, 'Your resolvers have been setup!', [ 'Listed in order they are:', @RESOLVERS ] );
    if ( $gotns < 2 ) {
        push @output, ['Warning: You only specified one resolver!  If this DNS server fails, your server may not function.  You should go back and specify additional resolvers.'];
    }
    return @output;
}

1;
