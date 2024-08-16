package Cpanel::WHMAPI;

# cpanel - Cpanel/WHMAPI.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

our $VERSION = 1.0;

my $has_Whostmgr_UI = 0;

eval '
    local $SIG{__DIE__} = "DEFAULT";
    use Whostmgr::UI; # Hide Dependency from bin/depend checker.
    $has_Whostmgr_UI=1;
    ';

sub setstatus {
    if ($has_Whostmgr_UI) { goto &Whostmgr::UI::setstatus; }
    if (@_)               { print $_[0] . "\n"; }
}

sub setstatusdone {
    if ($has_Whostmgr_UI) { goto &Whostmgr::UI::setstatusdone; }
    if (@_)               { print $_[0] . "\n"; }
}

sub clearstatus {
    if ($has_Whostmgr_UI) { goto &Whostmgr::UI::clearstatus; }
    if (@_)               { print $_[0] . "\n"; }
}

sub status_cmd {
    my @CMD = @_;
    my $data;

    my $zpid = open( READCHLD, "-|" );
    if ($zpid) {
        while (<READCHLD>) {
            print;
            $data .= $_;
        }
        close(READCHLD);
    }
    else {
        open( STDERR, ">&STDOUT" );
        exec @CMD;
        exit(1);
    }
    return $data;
}

sub status_note {
    print $_[0];
    return $_[0];
}

1;
