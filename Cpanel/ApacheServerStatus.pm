package Cpanel::ApacheServerStatus;

# cpanel - Cpanel/ApacheServerStatus.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Hulk::Constants ();

# Cannot be used due to safe run req need a file to stat for size
#use Cpanel::Config::Httpd   ();

#perl -MCpanel::ApacheServerStatus -MData::Dumper -e 'my $server_status = Cpanel::ApacheServerStatus->new(); print Dumper($server_status->get_status_by_pid(5178)); '
#perl -MCpanel::ApacheServerStatus -MData::Dumper -e 'my $server_status = Cpanel::ApacheServerStatus->new(); print Dumper($server_status); '

sub new {
    my ($class) = @_;

    my $obj = {};

    bless $obj, $class;

    my $html = $obj->fetch_server_status_html();

    $html =~ m/<table[^\>]*>(.*?)<\/table[^\>]*>/is;

    my $inner_table = $1;
    $inner_table =~ s/[\r\n\0]//g;
    my $line_count = 0;

    my ( @index, @data, %server_status );

    while ( $inner_table =~ m/<tr[^\>]*>(.*?)<\/tr[^\>]*>/isg ) {
        my $contents = $1;
        @data = map { s/^\s+//; s/\s+$//; lc $_; } ( $contents =~ m/(?:<[^\>]+>)+([^\<]+)/isg );
        if ( $line_count == 0 ) {
            @index = @data;
        }
        else {
            my $count      = 0;
            my %named_data = map { $index[ $count++ ] => $_; } @data;
            $server_status{ $named_data{'pid'} } = \%named_data;

        }
        $line_count++;
    }

    $obj->{'server_status'} = \%server_status;

    return $obj;
}

sub get_status_by_pid {
    my ( $self, $pid ) = @_;

    return $self->{'server_status'}->{$pid};

}

sub get_apache_port {
    if ( open( my $ap_port_fh, '<', '/var/cpanel/config/apache/port' ) ) {
        my $port_txt = readline($ap_port_fh);
        chomp($port_txt);
        if ( $port_txt =~ m/:/ ) {
            return ( split( m/:/, $port_txt ) )[1];
        }
        elsif ( $port_txt =~ /^[0-9]+$/ ) {
            return $port_txt;
        }
    }
}

sub fetch_server_status_html {
    my ($self) = @_;

    my $port = 80;
    my $html;

    eval {
        my $socket_scc;
        if ( !socket( $socket_scc, $Cpanel::Hulk::Constants::AF_INET, $Cpanel::Hulk::Constants::SOCK_STREAM, $Cpanel::Hulk::Constants::PROTO_TCP ) || !$socket_scc ) {
            die "Could not setup tcp socket for connection to $port: $!";
        }
        if ( !connect( $socket_scc, pack( 'S n a4 x8', $Cpanel::Hulk::Constants::AF_INET, $port, ( pack 'C4', ( split /\./, "127.0.0.1" ) ) ) ) ) {
            my $non_default_port = $self->get_apache_port();
            if ( $non_default_port && $non_default_port != $port ) {
                if ( !connect( $socket_scc, pack( 'S n a4 x8', $Cpanel::Hulk::Constants::AF_INET, $non_default_port, ( pack 'C4', ( split /\./, "127.0.0.1" ) ) ) ) ) {
                    die "Unable to connect to port $non_default_port on 127.0.0.1: $!";

                }
            }
        }

        syswrite( $socket_scc, "GET /whm-server-status HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n" );

        local $/;

        $html = readline($socket_scc);

        close($socket_scc);
    };

    $html;
}

1;
