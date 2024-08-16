package Whostmgr::PleskWordPressToolkit;

# cpanel - Whostmgr/PleskWordPressToolkit.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Pkgr ();
use Cpanel::OS   ();

use constant {
    INSTALL_SCRIPT => 'https://wp-toolkit.plesk.com/cPanel/installer.sh',
    PKG            => 'wp-toolkit-cpanel',

    # This touch file is not used by this module. It is only used by
    # Cpanel::TaskProcessors::WPTK, which itself is only used when
    # installing WP Toolkit as part of the initial cPanel installation.
    DISABLE_TOUCH_FILE => '/var/cpanel/nowptoolkit'
};

sub _handle_output ($msg) {
    chomp $msg;
    return unless $msg =~ m/\S/;            # ignore lines without content;
    $msg =~ s/\n{2,}/\n/g;                  # compact multiple newlines together
    print "$msg\n";
    return;
}

sub _to_bool ($input) {
    return $input ? 1 : 0;
}

sub is_supported () {
    return _to_bool( Cpanel::OS::supports_3rdparty_wpt() );
}

sub is_installed () {
    return _to_bool( Cpanel::Pkgr::is_installed(PKG) );
}

sub _is_inode_capable () {
    require Cpanel::Filesys::Info;

    my $inodes_free = Cpanel::Filesys::Info::_all_filesystem_info()->{'/'}->{'inodes_free'} // 0;

    return _to_bool( $inodes_free >= 20000 );
}

sub install ( $cb = \&_handle_output ) {
    require File::Temp;
    require HTTP::Tiny;
    require Cpanel::SafeRun::Object;
    require Cpanel::CPAN::IO::Callback::Write;

    my ( $fh, $filename ) = File::Temp::tempfile( "WPKT_XXXXXXX", TMPDIR => 1, UNLINK => 1 );
    my $http = HTTP::Tiny->new( verify_SSL => 1 );
    my $resp = $http->mirror( INSTALL_SCRIPT, $filename );
    die sprintf( "Failed [resp status: %s]!\n", $resp->{status} ) unless $resp->{success};

    # This will not be presented to the user as the WHM Marketplace will not
    # generate a link if the platform is not supported. See RTD-867
    if ( !is_supported ) {
        die "Install is not supported on the targeted distro";
    }

    my $write = Cpanel::CPAN::IO::Callback::Write->new($cb);

    my $saferun = Cpanel::SafeRun::Object->new(
        'program'      => '/bin/bash',
        'read_timeout' => 300,
        'timeout'      => 1200,
        'args'         => [$filename],
        'stdout'       => $write,
        'stderr'       => $write
    );

    if ( $saferun->CHILD_ERROR() ) {
        $cb->( sprintf( "WPTK Install Error: " . $saferun->autopsy() ) );
    }
    else {
        $cb->( sprintf("WPTK Install Complete") );
    }

    return is_installed;

}

1;

__END__

=head1 NAME

Whostmgr::PleskWordPressToolkit - Manage a Plesk WP Toolkit installation

=head1 SYNOPSIS

    # Example use case
    if ( is_supported && ! is_installed ) {
        install;
    }

=head1 DESCRIPTION

This module facilitates the install of WP Toolkit.

=head1 FUNCTIONS

=over 6

=item install -> Bool

Installs, and then returns the subsequent result of L<is_installed> to indicate
success or failure. Note L<install> will die if the L<is_supported> test does not
pass.

=item is_supported -> Bool

Predicate that tells you whether or not we support the install.

=item is_installed -> Bool

Predicate that returns whether or not the installation has occurred.

=back
