
# cpanel - Cpanel/FSTest.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::FSTest;

#

sub FSTest_init { }

sub api2_dirisempty {
    my %OPTS       = @_;
    my $dir        = $OPTS{'dir'};
    my $files_only = $OPTS{'files_only'};
    my $regex_ext  = $OPTS{'regex_ext'};

    $Cpanel::CPVAR{'last_dir_empty'} = 1;

    if ( !-d $dir ) {
        return;
    }

    opendir( my $dir_fh, $dir );
    while ( my $file = readdir($dir_fh) ) {
        if ( $file =~ /^\.+$/ || ( $files_only && -d $dir . '/' . $file ) || ( $regex_ext && $file !~ /\.($regex_ext)/ ) ) { next; }
        $Cpanel::CPVAR{'last_dir_empty'} = 0;
        closedir($dir_fh);
        return;
    }
    closedir($dir_fh);

    return;
}

our %API = (
    dirisempty => { allow_demo => 1 },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
