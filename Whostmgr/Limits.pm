package Whostmgr::Limits;

# cpanel - Whostmgr/Limits.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This file is a circular dependency with Whostmgr/Limits/PackageLimits.pm.
#----------------------------------------------------------------------

use strict;
use Cpanel::CachedDataStore                     ();
use Cpanel::ConfigFiles                         ();
use Cpanel::Transaction::File::LoadConfigReader ();
use Cpanel::Transaction::File::LoadConfig       ();
use Whostmgr::Packages::Fetch                   ();
use Whostmgr::Limits::PackageLimits             ();
use Whostmgr::Limits::Resellers                 ();
use Whostmgr::Limits::Exceed                    ();

my %DATASTORE_CACHE;
my $now;

*loaddatastore            = *Cpanel::CachedDataStore::loaddatastore;
*load_all_reseller_limits = *Whostmgr::Limits::Resellers::load_all_reseller_limits;
*saveresellerlimits       = *Whostmgr::Limits::Resellers::saveresellerlimits;
*load_reseller_datastore  = *Whostmgr::Limits::Resellers::load_reseller_datastore;
*load_resellers_limits    = *Whostmgr::Limits::Resellers::load_resellers_limits;
*would_exceed_limit       = *Whostmgr::Limits::Exceed::would_exceed_limit;

{
    my $current_acls;

    sub _validate_acls {
        my ( $value, $opts ) = @_;

        return unless $value && ref $value eq 'SCALAR' && $opts && ref $opts eq 'HASH';
        if ( !defined $current_acls ) {
            require Whostmgr::ACLS;
            Whostmgr::ACLS::init_acls();
            $current_acls = { map { $_ => undef } keys %Whostmgr::ACLS::ACL };
        }

        $$value = join ',', grep {
            s/^\s+//;
            s/\s+$//;
            my $known = exists $current_acls->{$_};
            if ( !$known ) {
                $opts->{warnings}->{'unknown-acls'} ||= [];
                push @{ $opts->{warnings}->{'unknown-acls'} }, $_;
            }
            $known
          }
          split /\s*,\s*/, $$value;

        return;
    }
}

sub import_reseller_config {
    my (%OPTS) = @_;

    my $backupdir             = $OPTS{'dir'};
    my $new_reseller_username = $OPTS{'newuser'};
    my $old_reseller_username = $OPTS{'olduser'} || $new_reseller_username;

    die "import_reseller_config requires the directory to read the config from." if !$backupdir;
    die "import_reseller_config requires the reseller to read the config for."   if !$new_reseller_username;

    my @to_check = (
        [ 'resellers', $Cpanel::ConfigFiles::RESELLERS_FILE, \&_validate_acls ],
        [ 'resellers-nameservers', $Cpanel::ConfigFiles::RESELLERS_NAMESERVERS_FILE ],
    );

    foreach my $files_ar (@to_check) {
        my ( $resfile, $system_resfile, $validator ) = @$files_ar;

        next if !-f "$backupdir/$resfile";

        local $@;

        my $src_data = eval { Cpanel::Transaction::File::LoadConfigReader->new( path => "$backupdir/$resfile", delimiter => ':', ) };
        return ( 0, $@ ) if !$src_data;

        next if !$src_data->has_entry($old_reseller_username);
        my $value = $src_data->get_entry($old_reseller_username);
        $validator->( \$value, \%OPTS ) if $validator && ref $validator eq 'CODE';

        if ( $resfile eq 'resellers' && $OPTS{'pkg_archive_version'} < 4 ) {

            # Automatically add the default ACLs to resellers
            # from older versions.
            require Whostmgr::ACLS::Data;
            $value .= length($value) && substr( $value, -1 ) ne ',' ? ',' : '';    # Add a comma when needed
            $value .= join ',', @{ Whostmgr::ACLS::Data::get_default_acls() };
        }

        #Ensure that we don't alter the permissions of the in-use files.
        my $perms = ( stat $system_resfile )[2] & 0777 || 0644;

        my $transaction = eval { Cpanel::Transaction::File::LoadConfig->new( path => $system_resfile, delimiter => ':', permissions => $perms, ) };
        return ( 0, $@ ) if !$transaction;

        $transaction->set_entry( $new_reseller_username => $value );

        my ( $save_ok, $save_err ) = $transaction->save( do_sort => 1 );
        return ( 0, $save_err ) if !$save_ok;

        my ( $close_ok, $close_err ) = $transaction->close();
        return ( 0, $close_err ) if !$close_ok;
    }
    return 1;
}

## via xfer's ::restorecpmove
sub import_reseller_limits {
    my (%OPTS) = @_;

    my $dir                   = $OPTS{'dir'};
    my $new_reseller_username = $OPTS{'newuser'};
    my $old_reseller_username = $OPTS{'olduser'} || $new_reseller_username;

    die "import_reseller_limits requires the directory to read the limits from." if !$dir;
    die "import_reseller_limits requires the reseller to read the limits for."   if !$new_reseller_username;

    my $reseller_limits_archive = "$dir/my_reseller-limits.yaml";
    my $package_limits_archive  = "$dir/my_package-limits.yaml";

    return if !-e $reseller_limits_archive && !-e $package_limits_archive;

    # Usage is safe as we own /var/cpanel and the dir
    my $import_reseller_limits = Cpanel::CachedDataStore::loaddatastore( $dir . '/my_reseller-limits.yaml', 0 );

    # Usage is safe as we own /var/cpanel and the dir
    my $import_package_limits = Whostmgr::Limits::PackageLimits->load( 0, "$dir/my_package-limits.yaml" );

    # Usage is safe as we own /var/cpanel and the dir
    my $reseller_limits = load_reseller_datastore(1);

    # Usage is safe as we own /var/cpanel and the dir
    my $package_limits = Whostmgr::Limits::PackageLimits->load(1);

    if ( $import_reseller_limits->{'data'}{$old_reseller_username} ) {
        $reseller_limits->{'data'}{$new_reseller_username} = $import_reseller_limits->{'data'}{$old_reseller_username};
    }
    else {
        delete $reseller_limits->{'data'}{$new_reseller_username};
    }

    my %ARGS = (
        'source_package_limits' => $import_package_limits,    #
        'target_package_limits' => $package_limits,           #
        'old_reseller_username' => $old_reseller_username,    #
        'new_reseller_username' => $new_reseller_username,    #
    );

    _copy_package_limits(%ARGS);
    _remove_nonexistant_package_limits(%ARGS);

    saveresellerlimits($reseller_limits);

    $package_limits->cleanup();
    $package_limits->save();

    return 1;
}

sub _copy_package_limits {
    my (%OPTS) = @_;

    my $source_package_limits = $OPTS{'source_package_limits'};
    my $target_package_limits = $OPTS{'target_package_limits'};
    my $old_reseller_username = $OPTS{'old_reseller_username'};
    my $new_reseller_username = $OPTS{'new_reseller_username'};

    my $ar_pkg_names               = $source_package_limits->list_packages();
    my $target_package_limits_data = $target_package_limits->{'data'};
    my $source_package_limits_data = $source_package_limits->{'data'};

    # Only store limits that affect us
    for my $pkg_name (@$ar_pkg_names) {
        foreach my $LIMIT ( keys %{ $source_package_limits_data->{$pkg_name} } ) {
            foreach my $LIMITTYPE ( keys %{ $source_package_limits_data->{$pkg_name}{$LIMIT} } ) {
                next if !exists $source_package_limits_data->{$pkg_name}{$LIMIT}{$LIMITTYPE}{$old_reseller_username};

                my $target_pkg_name = $pkg_name;
                $target_pkg_name =~ s/^\Q$old_reseller_username\E_/$new_reseller_username\_/ if $old_reseller_username ne $new_reseller_username;

                $target_package_limits_data->{$target_pkg_name}{$LIMIT}{$LIMITTYPE}{$new_reseller_username} =
                  $source_package_limits_data->{$pkg_name}{$LIMIT}{$LIMITTYPE}{$old_reseller_username};
            }
        }
    }

    return 1;
}

sub _remove_nonexistant_package_limits {
    my (%OPTS) = @_;

    my $source_package_limits = $OPTS{'source_package_limits'};
    my $target_package_limits = $OPTS{'target_package_limits'};
    my $old_reseller_username = $OPTS{'old_reseller_username'};
    my $new_reseller_username = $OPTS{'new_reseller_username'};

    # remove any limits that are not in the import
    my $ar_pkg_names               = $target_package_limits->list_packages();
    my $target_package_limits_data = $target_package_limits->{'data'};
    my $source_package_limits_data = $source_package_limits->{'data'};

    # Only store limits that affect us
    for my $pkg_name (@$ar_pkg_names) {
        foreach my $LIMIT ( keys %{ $target_package_limits_data->{$pkg_name} } ) {
            foreach my $LIMITTYPE ( keys %{ $target_package_limits_data->{$pkg_name}{$LIMIT} } ) {
                if ( exists $target_package_limits_data->{$pkg_name}{$LIMIT}{$LIMITTYPE}{$new_reseller_username} ) {

                    my $source_pkg_name = $pkg_name;
                    $source_pkg_name =~ s/^\Q$new_reseller_username\E_/$old_reseller_username\_/ if $new_reseller_username ne $old_reseller_username;

                    if ( !exists $source_package_limits_data->{$source_pkg_name}{$LIMIT}{$LIMITTYPE}{$old_reseller_username} ) {
                        delete $target_package_limits_data->{$pkg_name}{$LIMIT}{$LIMITTYPE}{$new_reseller_username};
                    }
                }
            }
        }
    }

    return 1;
}

## via the WHM "Reseller Center"
sub set_default_package_limits {
    my $reseller = shift;

    if ( !$reseller ) { return; }
    my $package_limits = Whostmgr::Limits::PackageLimits->load(1);

    ## CASE 33435: iterates over packages as found in /v/cp/packages (not the package-limits file).
    ##   Fixes a bug where a newly created package would not have any associated reseller limited
    ##   by it. The cleanup below takes care of the deprecated packages that $reseller might be
    ##   associated with.
    #OUT#my $ar_pkg_names = packagelimits_list_packages($package_limits);
    my $ar_pkg_names = Whostmgr::Packages::Fetch::_load_package_list();

    foreach my $pkg_name (@$ar_pkg_names) {
        if ( $pkg_name =~ /^\Q$reseller\E_/ ) {
            $package_limits->create_for_reseller( $pkg_name, $reseller, 1 );
        }
        else {
            $package_limits->delete_reseller( $pkg_name, $reseller );
        }
    }
    $package_limits->cleanup();
    return $package_limits->save();
}

sub can_set_unlimited {
    return Whostmgr::ACLS::hasroot() || !Whostmgr::Limits::load_resellers_limits()->{'limits'}{'resources'}{'enabled'} ? 1 : 0;
}

1;
