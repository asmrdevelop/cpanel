package Whostmgr::Remote::Parser::Scp;

# cpanel - Whostmgr/Remote/Parser/Scp.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Whostmgr::Remote::Parser';

use Cpanel::Exception ();
use Cpanel::Locale    ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->{'_calls_without_change'} = 0;
    $self->{'_bytes_processed'}      = 0;
    $self->{'percent_callback'}      = $OPTS{'percent_callback'};
    $self->{'remote_file_size'}      = $OPTS{'remote_file_size'};

    return 1;
}

sub _parse_nondata_line {
    my ( $self, $line ) = @_;

    if ( $line =~ m/^==sshcontrolsize=([^=\n]+)/ ) {
        my $bytes = $1;
        if ( $bytes == $self->{'_bytes_processed'} ) {
            $self->{'_calls_without_change'}++;
            if ( $self->{'_calls_without_change'} >= $self->{'timeout'} ) {
                print "… Timeout during scp session …\n";
                die Cpanel::Exception::create( 'RemoteSCPTimeout', 'The [asis,scp] session timed out after [quant,_1,second,seconds].', [ $self->{'timeout'} ] );
            }
        }
        else {
            $self->{'_calls_without_change'} = 0;
            $self->{'_bytes_processed'}      = $bytes;
            if ( $self->{'remote_file_size'} ) {
                my $percentage = int( ( $bytes / $self->{'remote_file_size'} ) * 100 );
                $self->{'percent_callback'}->($percentage) if $self->{'percent_callback'};
                print $self->_locale()->maketext( "Progress [numf,_1]%", $percentage ) . "\n";
            }
            else {
                print $self->_locale()->maketext( "Processed [quant,_1,byte,bytes].", $bytes ) . "\n";
            }
        }
    }

    return 1;
}

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

1;
