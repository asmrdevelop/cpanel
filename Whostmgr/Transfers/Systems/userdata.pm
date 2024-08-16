package Whostmgr::Transfers::Systems::userdata;

# cpanel - Whostmgr/Transfers/Systems/userdata.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
# RR Audit: JNK, FG

use base qw(
  Whostmgr::Transfers::SystemsBase::userdataBase
  Whostmgr::Transfers::SystemsBase::EA4
);

use Cpanel::Locale                      ();
use Cpanel::FileUtils::Copy             ();
use Cpanel::Config::userdata::Constants ();
use Cpanel::Config::userdata::Guard     ();
use Cpanel::Config::userdata::Load      ();

# Restore Ruby on Rails data, referencing scripts/securerailsapps for
# implementation details
my @RAILS_FILES = qw(
  ruby-on-rails.db
  ruby-on-rails-rewrites.db
  applications.json
);

my @APACHE_VHOST_TEMPLATE_FILE_KEYS = qw(
  custom_vhost_template_ap1
  custom_vhost_template_ap2
);

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores website configuration ([asis,userdata]).') ];
}

sub get_restricted_available {
    return 1;
}

sub get_restricted_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('Restricted Restore does not restore the entire [asis,userdata] file; instead, the system will create a new one and copy in certain information. Customizations to the [asis,userdata] file in the archive will not be in the newly-created [asis,userdata] file.') ];
}

sub unrestricted_restore {
    my ($self) = @_;

    $self->start_action("Restoring userdata…\n");

    my $newuser = $self->newuser();

    my ( $ud_ok, $dir_userdata ) = $self->find_extracted_userdata_dir();
    return ( 0, $dir_userdata ) if !$ud_ok;

    ## ? when would this be the case? an older version? when the name changes during a transfer?
    if ( !$dir_userdata ) {
        $self->out("No userdata included.");
        return 1;
    }

    foreach my $rails_file (@RAILS_FILES) {
        my $src = "$dir_userdata/$rails_file";

        next if !-f $src;

        my $dest = "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$newuser/$rails_file";

        my ( $copy_ok, $copy_err ) = Cpanel::FileUtils::Copy::safecopy( $src, $dest );
        if ( !$copy_ok ) {
            return ( 0, "userdata restore failed: $copy_err" );
        }
    }

    my $extractdir = $self->extractdir();

    $self->_restore_for_each_vhost(
        sub {
            my ( $vhname, $original_userdata, $guard, $guard_userdata ) = @_;

            foreach my $key ( keys %{$original_userdata} ) {

                # We don't properly register IPv6 addresses on the system at the
                # moment.
                next if $key eq 'ipv6';
                if ( !exists $guard_userdata->{$key} ) {
                    $guard_userdata->{$key} = $original_userdata->{$key};
                }
            }
            $self->normalize_userdata_ea4_phpversion($guard_userdata);

            $self->_restore_custom_docroot_if_valid( $vhname, $original_userdata, $guard_userdata );

            foreach my $key (@APACHE_VHOST_TEMPLATE_FILE_KEYS) {
                next if !exists $original_userdata->{$key};

                my ($fname) = $original_userdata->{$key} =~ m{([^/]+)\z};

                my $archive_path = "$dir_userdata/$fname";
                next if !-e $archive_path;

                my $installed_path = "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$newuser/$fname";

                my ( $ok, $err ) = Cpanel::FileUtils::Copy::copy( $archive_path, $installed_path );
                $self->warn($err) if !$ok;

                $guard_userdata->{$key} = $installed_path;
            }

            # PHP-FPM the yaml config file is transferred over but not made
            # active as we do not know the status of the php.

            my $fpm_yaml = "$dir_userdata/$vhname" . ".php-fpm.yaml";
            if ( -e $fpm_yaml ) {
                my $installed_path = "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$newuser/$vhname.php-fpm.yaml.transferred";

                my ( $ok, $err ) = Cpanel::FileUtils::Copy::copy( $fpm_yaml, $installed_path );
                $self->warn($err) if !$ok;
            }

            $guard->save();
        }
    );

    return 1;
}

sub _old_homedir_path_to_new_homedir_path {
    my ( $self, $vhname, $path ) = @_;

    my $new_homedir = $self->{'_utils'}->homedir();
    my $extractdir  = $self->extractdir();
    my ( $old_ok, $oldhomedirs_ref ) = $self->{'_archive_manager'}->get_old_homedirs();

    if ( !$old_ok ) {
        $self->utils()->add_skipped_item( $self->_locale()->maketext( "The system did not restore the previous document root for “[_1]” because an error prevented the system from retrieving a list of former home directories: [_1]", $vhname, $oldhomedirs_ref ) );
        return;
    }

    if ( !@{$oldhomedirs_ref} ) {
        $self->utils()->add_skipped_item( $self->_locale()->maketext( "The system did not restore the previous document root for “[_1]” because the archive does not contain a list of the user’s previous home directories, or that list is empty.", $vhname ) );
        return;
    }

    foreach my $old_homedir ( sort { length $b <=> length $a } @{$oldhomedirs_ref} ) {
        if ( $path =~ s{^\Q$old_homedir\E(/|\z)}{$new_homedir$1} ) {
            return $path;
        }
    }

    $self->utils()->add_skipped_item( $self->_locale()->maketext( "The previous document root for “[_1]” was not restored because “[_2]” is outside the previous home directory paths [list_and_quoted,_3].", $vhname, $path, $oldhomedirs_ref ) );

    return;
}

sub restricted_restore {
    my ($self) = @_;

    my $can_only_be_1_re         = qr<\A1\z>;
    my $can_only_be_1_or_neg1_re = qr<\A-?1\z>;

    #TODO in 11.48: Move this out of this function since
    #it makes more sense to build this hash at compile time.
    my %KEYS_TO_COPY_IN_RESTRICTED_MODE = (
        'userdirprotect'        => $can_only_be_1_or_neg1_re,
        'phpopenbasedirprotect' => $can_only_be_1_or_neg1_re,
        'phpversion'            => qr<\Aea-php\d\d\z>,
    );

    $self->_restore_for_each_vhost(
        sub {
            my ( $vhname, $ud_hr, $guard, $guard_userdata ) = @_;

            for my $key ( keys %KEYS_TO_COPY_IN_RESTRICTED_MODE ) {
                next if !length $ud_hr->{$key};
                next if $ud_hr->{$key} !~ $KEYS_TO_COPY_IN_RESTRICTED_MODE{$key};
                $guard_userdata->{$key} = $ud_hr->{$key};
            }
            $self->normalize_userdata_ea4_phpversion($guard_userdata);

            $self->_restore_custom_docroot_if_valid( $vhname, $ud_hr, $guard_userdata );

            $guard->save();
        }
    );

    return 1;
}

sub _restore_custom_docroot_if_valid {
    my ( $self, $vhname, $original_userdata, $guard_userdata ) = @_;

    if ( $original_userdata->{'documentroot'} ) {
        my $new_path = $self->_old_homedir_path_to_new_homedir_path( $vhname, $original_userdata->{'documentroot'} );
        if ($new_path) {
            if ( $new_path ne $guard_userdata->{'documentroot'} ) {
                $guard_userdata->{'documentroot'} = $new_path;
                $self->out( $self->_locale()->maketext( "Restored custom “[_1]” for the website “[_2]” as “[_3]”.", 'documentroot', $vhname, $new_path ) );
            }
        }
    }

    return;
}

sub _restore_for_each_vhost {
    my ( $self, $todo_cr ) = @_;

    my $newuser = $self->newuser();

    #Sometimes restorations are for brand-new accounts;
    #other times they restore a backup over an existing account.
    my $ud_main = Cpanel::Config::userdata::Guard->new($newuser);

    #Would be nice to have the Cpanel::Config::WebVhosts OO interface here.
    my @vhosts = (
        $ud_main->data()->{'main_domain'},
        @{ $ud_main->data()->{'sub_domains'} || [] },
    );

    #NOTE: SSL userdata files are part of a separate SSL restore.
    foreach my $vhname (@vhosts) {
        $self->out( $self->_locale()->maketext( "Restoring userdata for “[_1]” …", $vhname ) );

        my ( $ud_ok, $original_userdata ) = $self->read_extracted_userdata_for_domain($vhname);
        if ( !$ud_ok ) {
            $self->warn( $self->_locale()->maketext( "The system failed to load original userdata for “[_1]” because of an error: [_2]", $vhname, $original_userdata ) );
        }
        elsif ( !$original_userdata ) {
            $self->out(
                $self->_locale()->maketext(
                    'The system did not find a [asis,userdata] file for “[_1]” in the archive. The archive may be incomplete or you may be transferring from a non-cPanel [output,amp] WHM system.',
                    $vhname
                )
            );

            # Also run scripts/updateuserdomains in this scenario, as that will fix this problem going forward (unless we're intentionally skipping that).
            # Otherwise things will be kind of messed up -- you won't be able to delete the account till this runs, for example
            require Cpanel::Userdomains;
            Cpanel::Userdomains::updateuserdomains();
        }
        else {

            #We need to know this to open the Guard object
            #for the vhost-specific userdata file.
            my $ud_exists = Cpanel::Config::userdata::Load::user_has_domain( $newuser, $vhname );

            #TODO: error handling
            my $guard          = Cpanel::Config::userdata::Guard->new( $newuser, $vhname, $ud_exists ? () : { main_data => $ud_main->data() } );
            my $guard_userdata = $guard->data();

            $todo_cr->( $vhname, $original_userdata, $guard, $guard_userdata );
            undef $guard;

            #Prevent this module from ballooning memory usage.
            #(That could otherwise happen if the archive has
            #1,000s of vhosts.)
            Cpanel::Config::userdata::Load::clear_memory_cache_for_user_vhost( $newuser, $vhname );
        }
    }

    $ud_main->abort();

    return;
}

1;
