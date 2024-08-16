# cpanel - Cpanel/Market/ProductRequirements.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Market::ProductRequirements;

use cPstrict;

use Cpanel::Sys::Info                     ();
use Cpanel::OS                            ();
use Cpanel::OSSys::Env                    ();
use Cpanel::Filesys::Info                 ();
use Cpanel::Autodie                       ();
use Cpanel::Transaction::File::JSON       ();
use Cpanel::Transaction::File::JSONReader ();

our $state_dir = "/var/cpanel/market/supported_products";

sub not_supported ( $appconfig, $app, $lh ) {

    #Because Cpanel::Locale is essentially unmockable due to BEGIN block, we have to alter our code to fit
    my $check_nice = {
        envtype   => $lh->maketext("Your system may have issues installing this product due to an unsupported Server Type."),
        ram       => $lh->maketext("Your system may have issues installing this product due to insufficient RAM."),
        disk      => $lh->maketext("Your system may have issues installing this product due to an insufficiently large root partition."),
        os        => $lh->maketext("Your system may have issues installing this product due to an unsupported Operating System."),
        osversion => $lh->maketext("Your system may have issues installing this product due to an unsupported Operating System Version."),
    };

    my $cached = _cached( $app, $appconfig->{key} );
    return $cached if defined $cached;

    my $state = {};

    foreach my $check (qw{envtype ram disk}) {
        next unless defined $appconfig->{$check};
        my $sub = "Cpanel::Market::ProductRequirements::_supported_$check";

        #Secret technique for evading 'no strict refs'
        if ( defined &{ \&{$sub} } ) {
            $state->{$check} = $check_nice->{$check} unless &{ \&{$sub} }( @{ $appconfig->{$check} } );
            next;
        }

        $sub = "Cpanel::Market::ProductRequirements::_minimum_$check" unless defined &{ \&{$sub} };
        my $results = &{ \&{$sub} }( $appconfig->{$check} );
        unless ( $results->{supported} ) {
            my $reason = $check_nice->{$check};
            if ( $results->{has} && $results->{needs} ) {
                $reason .= " " . $lh->maketext( "The system has [format_bytes,_1] but needs [format_bytes,_2].", $results->{has}, $results->{needs} );
            }
            $state->{$check} = $reason;
        }
    }

    if ( $appconfig->{os} && ref( $appconfig->{os} ) eq 'HASH' ) {

        my $system_os = lc( Cpanel::OS::distro() );    ## no critic(Cpanel::CpanelOS) Market design
        if ( exists $appconfig->{os}{$system_os} ) {

            if ( ref $appconfig->{os}{$system_os} eq 'ARRAY' ) {
                my $system_os_version = Cpanel::OS::major();    ## no critic(Cpanel::CpanelOS) Market OS check is based on major

                if ( !grep { $_ eq $system_os_version } @{ $appconfig->{os}{$system_os} } ) {
                    $state->{osversion} = $check_nice->{osversion};
                }
            }
        }
        else {
            $state->{os} = $check_nice->{os};
        }
    }

    return _cache_state( $app, $appconfig->{key}, $state );
}

sub _cached ( $app, $key ) {

    my $file = "$state_dir/$app\_$key";
    return unless eval { Cpanel::Autodie::exists($file) };

    #If we encounter an error, waste the file before returning undef
    my $cached = eval { Cpanel::Transaction::File::JSONReader->new( path => $file ) };
    if ( !$cached ) {
        unlink $file or warn;
        return $cached;
    }
    $cached = $cached->get_data();
    return $cached unless $cached;
    _ensure_cache_dir();

    #Invalidate cache after a day unless user have disabled this product from banner/marketplace
    if ( !$cached->{'disabled'} ) {
        my $ctime = ( stat($file) )[10] || 0;
        if ( $ctime < ( time() - 86400 ) ) {
            unlink($file) or warn "Could not delete cache '$file': $!";
            return undef;
        }
        return $cached;
    }
    return 0;
}

sub _cache_state ( $app, $key, $state = {} ) {
    _ensure_cache_dir();
    my $cache  = "$state_dir/$app\_$key";
    my $writer = Cpanel::Transaction::File::JSON->new( path => $cache );
    $writer->set_data($state);
    eval { $writer->save_or_die() } or warn;
    return $state;
}

sub _ensure_cache_dir {

    #Ensure presence of cachedir
    if ( !-d $state_dir ) {
        require File::Path;
        File::Path::make_path($state_dir) or warn "Could not create directory '$state_dir'!";
    }
    return;
}

sub _supported_envtype (@envtype_patterns) {
    my $envtype = lc( Cpanel::OSSys::Env::get_envtype() );

    #In case something has gone horribly wrong here
    return 0 unless $envtype;

    return !!scalar( grep { m/$envtype/ } @envtype_patterns );
}

sub _minimum_ram ($req) {
    my $info = Cpanel::Sys::Info::sysinfo();
    $info->{totalram} ||= 1;    #Avoid divide by 0 in worst case
    my $ram_mb = $info->{totalram} / 1048576;
    return $ram_mb > $req ? { supported => 1 } : { supported => 0, has => $info->{totalram}, needs => ( $req * 1048576 ) };
}

#For MSRs that don't specify minimum *free* disk space
sub _minimum_disk ($req) {

    #Blocks are in kilobytes here
    my %info  = Cpanel::Filesys::Info::filesystem_info('/');
    my $bfree = $info{blocks_free};
    $bfree = 1 if $bfree <= 0;
    my $bfree_mb = $bfree / 1024;
    return $bfree_mb > $req ? { supported => 1 } : { supported => 0, has => ( $bfree_mb * 1048576 ), needs => ( $req * 1048576 ) };
}

sub is_installed ($app_def) {
    require Cpanel::AppConfig;

    # accessio cedet principali
    return 2 if ( ref $app_def->{accessions} eq 'ARRAY' ) && grep { -f "$Cpanel::AppConfig::APPCONF_DIR/" . $_ . ".conf" } @{ $app_def->{accessions} };
    return 0 unless $app_def->{key} && -f "$Cpanel::AppConfig::APPCONF_DIR/" . $app_def->{key} . '.conf';
    return 1;
}

1;
__END__

=head1 Cpanel::Market::ProductRequirements

Utility library for determining whether a product is viable to use on this server.

=head1 SUBROUTINES

=head2 not_supported( HASHREF $app_definition, STRING $whostmgr_app, Cpanel::Locale $locale ) => STRING state

Returns a reason the system requirements from the provided app definition are not met.
If a string is returned rather than false, then the system does not support the provided application.

Caches the outcome of this calculation for 24 hours and stores an appropriately named symlink in /var/cpanel/market/supported_products.
The link pointer is the BOOL value of whether the product is supported or not, or the string "DISABLED" in the event the banner is user disabled.
Check is done per whostmgr app (page) it's displayed in; this allows permanent dismissal of an advert for users.

Warns in the event the cache or it's containing directory cannot be created, or a cachefile invalidated.

=head2 is_installed( HASHREF $app_definition ) => BOOL state

Return whether the product in question is installed or not by checking for existence of a file specific to the app's implementation.
