#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - t-dist/update-analysis/000-base.t       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Test2::V0;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;

use Cpanel::SafeRun::Errors   ();
use Cpanel::Services::Enabled ();
use Cpanel::Services::List    ();
use Cwd                       ();
use HTTP::Tiny                ();
use Cpanel::OS                ();

my $cpanel_dir = '/usr/local/cpanel';

my @binaries = cpanel_binaries();

is( scalar @binaries, 154, "binaries count" );

my $bin_version  = '11.' . get_bin_version();
my $file_version = get_file_version();
is( $bin_version, $file_version, 'Version file matches binary output' );
diag("bin: $bin_version, file: $file_version");

sub get_bin_version {
    my $version = Cpanel::SafeRun::Errors::saferunnoerror( "$cpanel_dir/cpanel", '-V' );
    chomp $version;
    $version =~ s/\s[^\d]*(\d+)[^\d]*$/\.$1/a;
    return $version;
}

sub get_file_version {
    my $filename = "$cpanel_dir/version";
    return if !-f $filename;
    my $fh;
    return if !open $fh, '<', $filename;
    my $contents = "";

    while ( my $line = <$fh> ) {
        $contents .= $line;
    }

    close $fh;
    chomp $contents;
    return $contents;
}

my $owd = Cwd::getcwd();
chdir $cpanel_dir or die;
my $error_count = 0;
for my $bin (@binaries) {
    ok( -x $bin, "$bin is executable" );
    my $out = Cpanel::SafeRun::Errors::saferunnoerror( "./$bin", '--bincheck' );

    #$out =~ s/^\s+|\s+$//gs;
    like( $out, qr/^BinCheck ok/m, "Bincheck for $bin passes" )
      or diag $out;
}
$error_count += cpphp_failed();
chdir $owd or die;
is( $error_count, 0, 'Bincheck passed' );

sub cpphp_failed {
    my $bin = '3rdparty/bin/php';
    if ( !-x $bin ) {
        diag("$bin not executable");
        return 1;
    }
    my $out = Cpanel::SafeRun::Errors::saferunnoerror( $bin, '-v' );
    $out =~ s/^\s+|\s+$//gs;
    if ( $out !~ m/^PHP/ ) {
        diag("$bin: $out");
        return 1;
    }
    return 0;
}

my $services_hashref = Cpanel::Services::List::get_service_list();
$error_count = 0;
for my $service ( keys %$services_hashref ) {
    $error_count += service_enabled_but_not_running($service);
}
is( $error_count, 0, 'All enabled core services running' );

sub service_enabled_but_not_running {
    my ($service) = @_;
    return 0 if 1 != Cpanel::Services::Enabled::is_enabled($service);

    my $script = "$cpanel_dir/scripts/restartsrv_$service";

    # No script, no problem.
    return 0 unless -x $script;

    my $out = Cpanel::SafeRun::Errors::saferunallerrors( $script, '--check' );
    chomp $out;
    if ( $out =~ m/is (?:down|not running)/ ) {
        diag("Service $service enabled but not running");
        return 1;
    }
    return 0;
}

$error_count = 0;
for my $username (
    qw(
    cpanel
    cpaneleximfilter
    cpaneleximscanner
    cpanellogin
    cpanelphpmyadmin
    cpanelphppgadmin
    cpanelroundcube
    )
) {
    $error_count += username_does_not_exist($username);
}
is( $error_count, 0, 'All cPanel user accounts in place' );

sub username_does_not_exist {
    my ($username) = @_;
    if ( !scalar getpwnam($username) ) {
        diag("Missing account $username");
        return 1;
    }
    return 0;
}

my $req           = HTTP::Tiny->new;
my $resp          = $req->get('http://localhost:2086/');
my $response_size = length $resp->{'content'} || 0;
ok( $response_size > 0, 'cpsrvd responds' );
like( $resp->{'status'}, qr/^(2\d\d|401)$/, 'cpsrvd responds successfully' );

done_testing();
exit;

sub cpanel_binaries {

    my $cpanelsync_file = "$cpanel_dir/.cpanelsync_binaries__forward_slash__" . Cpanel::OS::binary_sync_source();

    return unless -e $cpanelsync_file && !-z _;
    return unless open( my $fh, '<', $cpanelsync_file );

    my @binaries;
    while ( my $line = <$fh> ) {
        my ( $type, $file ) = split( '===', $line );
        ( $type && $type eq 'f' ) or next;
        $file =~ s{^\./}{};
        $file or next;

        push @binaries, $file;
    }

    return @binaries;
}
