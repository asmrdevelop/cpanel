package Cpanel::Exim::Reset;

# cpanel - Cpanel/Exim/Reset.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Logger              ();
use Cpanel::LoadFile            ();
use Cpanel::Config::FlushConfig ();
use Cpanel::Config::LoadConfig  ();
use Cpanel::SafeFile            ();
use Cpanel::Dir::Loader         ();
use Cpanel::Userdomains         ();

my $logger;

sub reset_all_exim_cfg_to_defaults {
    unlink(
        '/etc/exim.conf.local',         '/etc/exim.conf.localopts',         '/etc/exim.conf.localopts.shadow',
        '/etc/exim.conf.local.dry_run', '/etc/exim.conf.localopts.dry_run', '/etc/exim.conf/localopts.shadow.dry_run',
        '/etc/global_spamassassin_enable'
    );
    Cpanel::Userdomains::updateuserdomains('--force');

    return;
}

sub reset_acl_exim_cfg_to_defaults {
    my %OPTS = @_;
    my $file = ( $OPTS{'local'} ? $OPTS{'local'} : '/etc/exim.conf.local' );
    return if !-e $file;

    my @NEWCF;
    my $inaclblock = 0;
    my $exlock     = Cpanel::SafeFile::safeopen( \*EXIMLOCAL, '+<', $file );
    if ( !$exlock ) {
        $logger ||= Cpanel::Logger->new();
        $logger->warn("Could not edit $file");
        return;
    }
    while (<EXIMLOCAL>) {
        if (/^\%ACLBLOCK\%/) {
            $inaclblock = 1;
            next;
        }
        elsif ( $inaclblock && /^[@%]/ ) {
            $inaclblock = 0;
            push @NEWCF, $_;
        }
        elsif ($inaclblock) {
            next;
        }
        else {
            push @NEWCF, $_;
        }
    }
    seek( EXIMLOCAL, 0, 0 );
    print EXIMLOCAL join( '', @NEWCF );
    truncate( EXIMLOCAL, tell(EXIMLOCAL) );
    Cpanel::SafeFile::safeclose( \*EXIMLOCAL, $exlock );

    return;
}

sub reset_inserts_exim_cfg_to_defaults {
    unlink( '/etc/exim.conf.local', '/etc/exim.conf.local.dry_run' );
    return;
}

sub reset_cf_exim_cfg_to_defaults {
    foreach my $type (qw(cf replacecf)) {
        my %DISTCFS = map { $_ => undef } grep ( !m/^\s*#/, split( /\n/, Cpanel::LoadFile::loadfile("/usr/local/cpanel/etc/exim/$type.dist") ) );
        my $dir     = "/usr/local/cpanel/etc/exim/$type";
        my %BLOCKS  = Cpanel::Dir::Loader::load_multi_level_dir($dir);
        foreach my $block ( keys %BLOCKS ) {
            foreach my $cf ( @{ $BLOCKS{$block} } ) {
                unlink("$dir/$block/$cf") unless exists $DISTCFS{$cf};
            }
        }
        if ( opendir( my $dh, $dir ) ) {
            foreach my $cf ( readdir $dh ) {
                unlink("$dir/$cf") unless exists $DISTCFS{$cf};
            }
            closedir($dh);
        }
    }

    return;
}

sub disable_custom_acls {

    my %ACLS;
    my %ACLBLOCKS = Cpanel::Dir::Loader::load_multi_level_dir('/usr/local/cpanel/etc/exim/acls');
    foreach my $aclblock ( keys %ACLBLOCKS ) {
        foreach my $acl ( @{ $ACLBLOCKS{$aclblock} } ) {
            $acl =~ s/\.dry_run$//;
            $ACLS{$acl} = undef;
        }
    }

    my %DISTACLS = map { $_ => undef } grep ( !m/^\s*#/, split( /\n/, Cpanel::LoadFile::loadfile('/usr/local/cpanel/etc/exim/acls.dist') ) );

    my $file     = '/etc/exim.conf.localopts';
    my $conf_ref = Cpanel::Config::LoadConfig::loadConfig( $file, {}, '\s*=\s*', '^\s*[#;]', 0, 1 );
    foreach my $acl ( sort keys %ACLS ) {
        if ( !exists $DISTACLS{$acl} || $acl =~ /^custom_/ ) {
            $conf_ref->{ 'acl_' . $acl } = 0;
        }
    }

    Cpanel::Config::FlushConfig::flushConfig( $file, $conf_ref, '=' );

    return;
}

1;
