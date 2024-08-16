package Cpanel::Preparse;

# cpanel - Cpanel/Preparse.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Carp   ();
use Cpanel ();

sub new {
    my $self = {};
    bless($self);
    return ($self);
}

sub exec {
    my ( $self, $nstd, $page ) = @_;
    my ($ret);
    $nstd =~ s/\n$//g;
    $nstd = $nstd . "\n\n";
    $ENV{'CONTENT_LENGTH'} = length($nstd);

    $| = 1;
    die "can't get homedir" if not defined($Cpanel::homedir);

    if ( ( -f "$Cpanel::homedir/.cpanelpp" ) || ( !-e "$Cpanel::homedir/.cpanelpp" ) ) {
    }
    else {
        die "Can't create preparser temp file";
    }

    open( PPT, ">$Cpanel::homedir/.cpanelpp" );
    print PPT $nstd;
    print PPT $page;
    close(PPT);

    open( PPR, "/usr/local/cpanel/cpanel --pp|" );
    while (<PPR>) {
        $ret = $ret . $_;
    }
    close(PPR);

    #unlink("$Cpanel::homedir/.cpanelpp");

    return $ret;

}

1;
