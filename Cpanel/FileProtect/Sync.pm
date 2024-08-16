package Cpanel::FileProtect::Sync;

# cpanel - Cpanel/FileProtect/Sync.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This module only concerns the stored on/off FileProtect state.
#To enable or disable fileprotect, use scripts/enablefileprotect
#and scripts/disablefileprotect.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Config::Httpd::Perms         ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::Config::userdata::Load       ();
use Cpanel::Context                      ();
use Cpanel::FileProtect                  ();
use Cpanel::FileProtect::Constants       ();
use Cpanel::FileUtils::Read              ();
use Cpanel::Path::Dir                    ();
use Cpanel::PwCache                      ();
use Cpanel::SafeRun::Object              ();
use Cpanel::Exception                    ();
use Cpanel::Sys::Setsid::Fast            ();
use Cwd                                  ();
use List::Util                           ();

use constant _ENOENT => 2;

use Try::Tiny;

my $SETFACL_BIN = '/usr/bin/setfacl';

=head1 MODULE

C<Cpanel::FileProtect::Sync>

=head1 DESCRIPTION

C<Cpanel::FileProtect::Sync> provides

=cut

=head1 FUNCTIONS

=cut

*_webserver_runs_as_user = *Cpanel::Config::Httpd::Perms::webserver_runs_as_user;

#Used in testing.
sub _acls_are_on {
    return Cpanel::Config::LoadCpConf::loadcpconf_not_copy()->{'acls'} ? 1 : 0;
}

=head2 sync_user_homedir(USERNAME)

Fix the permission and ownership to more secure if FileProtect is on.

This function MUST be called in list context, or an exception is thrown.

=head3 ARGUMENTS

=over

=item USERNAME : string - required.

The name of the cPanel account to process.

=back

=head3 RETURNS

=over

=item List of C<Cpanel::Exception>s for problems encountered during the security hardening.

=back

=cut

sub sync_user_homedir {
    my ($username) = @_;

    Cpanel::Context::must_be_list();

    local $!;

    my @warnings;

    # We cannot use Cpanel::DomainLookup::DocRoot here because it uses the
    # userdata cache, which is built via the task queue after account creation,
    # while this code is run during account creation.
    my $user_homedir       = Cpanel::PwCache::gethomedir($username);
    my $user_htpasswds_dir = "$user_homedir/.htpasswds";

    my $main_domain = Cpanel::Config::userdata::Load::load_userdata_main($username)->{'main_domain'};
    die "User $username has no “main_domain” in userdata!" if !defined $main_domain;

    my $main_docroot = Cpanel::Config::userdata::Load::load_userdata( $username, $main_domain, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP )->{'documentroot'};
    die "User $username has no “documentroot” in userdata!" if !defined $main_docroot;

    my ( $user_uid, $user_gid ) = ( Cpanel::PwCache::getpwnam_noshadow($username) )[ 2, 3 ];
    my $nobody_gid = ( Cpanel::PwCache::getpwnam('nobody') )[3];

    my $subdomains_ar = Cpanel::Config::userdata::Load::get_subdomains($username);
    my @sub_docroots  = map {
        my $ud_ref = Cpanel::Config::userdata::Load::load_userdata( $username, $_, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );

        #Prevent ballooning memory usage in account restores.
        Cpanel::Config::userdata::Load::clear_memory_cache_for_user_vhost( $username, $_ );

        $ud_ref->{'documentroot'};
    } @$subdomains_ar;

    my $acls_are_on = _acls_are_on();

    my ( $dir_gid, $docroot_and_htpasswds_perms, $homedir_perms ) = _get_fileprotect_settings( $acls_are_on, $user_gid, $nobody_gid );

    #This is just thrown away if ACLs are not on.
    my @acl_dirs = (
        $user_homedir,
        $user_htpasswds_dir,
    );

    my $sync_cr = sub {
        my $dir = shift;
        _chown( \@warnings, $user_uid, $dir_gid, $dir );
        _chmod( \@warnings, $docroot_and_htpasswds_perms, $dir );
    };

    my $warn_cr = sub {
        my $msg = shift;
        $msg =~ s<\n.*><>;
        push @warnings, $msg;
    };

    my $err;

    # Only likely to fail if one of the docroots get removed in the middle of this
    try {
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            $user_uid,
            $dir_gid,
            sub {
                _chmod( \@warnings, $homedir_perms, $user_homedir );

                _make_htpasswds_dir( \@warnings, $user_homedir );
                _sync_htpasswds_dir( $user_htpasswds_dir, $sync_cr, \@acl_dirs );

                for my $docroot ( $main_docroot, @sub_docroots ) {
                    next if !length $docroot;

                    if ( !lstat $docroot ) {
                        if ( $! != _ENOENT() ) {

                            #preserve $! for -l below
                            local $!;

                            warn "stat($docroot): $!";
                        }

                        next;
                    }

                    $docroot = Cwd::abs_path($docroot) if -l _;

                    push( @acl_dirs, $docroot );
                    $sync_cr->($docroot);

                    for my $intermediate_dir ( Cpanel::Path::Dir::intermediate_dirs( $user_homedir, $docroot ) ) {
                        next if List::Util::any { $_ eq $intermediate_dir } @acl_dirs;
                        push @acl_dirs, $intermediate_dir;
                        $sync_cr->($intermediate_dir);
                    }
                }
            },
        );
    }
    catch {
        $err = $_;
    };

    push @warnings, $err if $err;

    if ($acls_are_on) {
        _set_acls_on_dirs( \@warnings, $username, @acl_dirs );
    }

    return @warnings;
}

=head2 protect_web_directory(USERNAME, DIR)

Perform the same actions that enabling/disabling FileProtect on a
specific web directory.

Notes:

 * This is intended to be called from an AdminBin or some similar root process.

=head3 ARGUMENTS

=over

=item USERNAME - string

The user who owns the directory.

=item DIR - string

The web directory to protect. There is special handling for the home folder and
for the .htpasswd directory.

=back

=head3 THROWS

=over

=item When a parameter is missing.

=item When any of the file system operation fail.

=item Possibly others related to reduction of privileges or querying other parts of the system.

=back

=cut

sub protect_web_directory {
    my ( $username, $dir ) = @_;

    die 'Missing username parameter' if !$username;
    die 'Missing dir parameter'      if !$dir;

    my @warnings;

    my $acls_are_on = _acls_are_on();

    my $user_homedir = Cpanel::PwCache::gethomedir($username);

    my ( $user_uid, $user_gid ) = ( Cpanel::PwCache::getpwnam_noshadow($username) )[ 2, 3 ];
    my $nobody_gid = ( Cpanel::PwCache::getpwnam('nobody') )[3];

    my ( $dir_gid, $docroot_and_htpasswds_perms, $homedir_perms ) = _get_fileprotect_settings( $acls_are_on, $user_gid, $nobody_gid );

    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        $user_uid,
        $dir_gid,
        sub {
            if ( $dir eq $user_homedir . '/.htpasswds' ) {
                _make_htpasswds_dir( \@warnings, $user_homedir );
                die $warnings[0] if @warnings;
            }

            _chown( \@warnings, $user_uid, $dir_gid, $dir );
            die $warnings[0] if @warnings;

            _chmod( \@warnings, ( $dir eq $user_homedir ? $homedir_perms : $docroot_and_htpasswds_perms ), $dir );
            die $warnings[0] if @warnings;
        }
    );

    if ($acls_are_on) {
        _set_acls_on_dirs( \@warnings, $username, $dir );
        die $warnings[0] if @warnings;
    }

    return 1;
}

sub _get_fileprotect_settings {
    my ( $acls_are_on, $user_gid, $nobody_gid ) = @_;

    my ( $homedir_perms, $dir_perms, $dir_gid );

    #FileProtect status does not matter for the home directory.
    if ($acls_are_on) {
        $homedir_perms = Cpanel::FileProtect::Constants::OS_ACLS_HOMEDIR_PERMS();
        $dir_perms     = Cpanel::FileProtect::Constants::FILEPROTECT_OR_ACLS_DOCROOT_PERMS();
        $dir_gid       = $user_gid;
    }
    else {
        # NOTE: When FileProtect is off and apache is running sites as nobody,
        # it seems counter intuitive, to get the user guid here, since this
        # means you have to set permissive permissions (WORLD READ + EXECUTE),
        # but you can't really do better by retaining the 'nobody' group since all
        # the sites on apache will run as 'nobody'. 'nobody' (0750) vs 'user' (755)
        # are basically the same from a hackers point of view. You can drop a php script
        # in your public_html folder and read anyone else folders on the server.
        $homedir_perms = Cpanel::FileProtect::Constants::DEFAULT_HOMEDIR_PERMS();
        $dir_perms     = _fileprotect_is_on()                               ? Cpanel::FileProtect::Constants::FILEPROTECT_OR_ACLS_DOCROOT_PERMS() : Cpanel::FileProtect::Constants::DEFAULT_DOCROOT_PERMS();
        $dir_gid       = _fileprotect_is_on() && !_webserver_runs_as_user() ? $nobody_gid                                                         : $user_gid;
    }

    return ( $dir_gid, $dir_perms, $homedir_perms );
}

sub _fileprotect_is_on {
    return Cpanel::FileProtect->is_on();
}

#Stubbed out in testing.
sub _set_acls_on_dirs {
    my ( $warnings_ar, $username, @acl_dirs ) = @_;

    my $run = Cpanel::SafeRun::Object->new(
        program => $SETFACL_BIN,
        args    => [
            '--remove-default',
            '--remove-all',
            '--modify' => 'group:nobody:x',
            '--modify' => 'group:mail:x',
            '--modify' => 'group:cpanel:x',
            '--modify' => 'group:mailnull:x',
            '--modify' => 'group:ftp:x',
            '--modify' => 'group:65535:x',
            '--',
            @acl_dirs,
        ],
        before_exec => sub {
            Cpanel::Sys::Setsid::Fast::fast_setsid();
            require Cpanel::AccessIds::SetUids;
            Cpanel::AccessIds::SetUids::setuids($username);

        },
    );
    if ( $run->CHILD_ERROR() ) {
        push @$warnings_ar, Cpanel::Exception->create_raw( $run->stdout() );
    }

    return;
}

sub _make_htpasswds_dir {
    my ( $warnings_ar, $path ) = @_;

    if ( !-d "$path/.htpasswds" ) {
        local $!;
        mkdir "$path/.htpasswds" or do {
            push @$warnings_ar, Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => "$path/.htpasswds", error => $! ] );
        };
    }

    return 1;
}

sub _sync_htpasswds_dir {
    my ( $htpasswds_dir, $sync_cr, $dirs_href ) = @_;

    $sync_cr->($htpasswds_dir);

    my @htpasswds_path;
    push @htpasswds_path, $htpasswds_dir;
    my $htpasswds_cr;    # Declared first so it can reference itself.
    $htpasswds_cr = sub {
        return if /^[.]/;                         # skip dotfiles/dotdirs
        push @htpasswds_path, $_;                 # Add this node to the working path (remember to pop the node before return)
        my $path = join q{/}, @htpasswds_path;    # Build full working path
        if ( !-l $path && -d $path ) {            # No links, only directories
            push @{$dirs_href}, $path;
            $sync_cr->($path);
            Cpanel::FileUtils::Read::for_each_directory_node( $path, $htpasswds_cr );    # Dive into this directory
        }
        pop @htpasswds_path;                                                             # Done with this node
        return;
    };

    Cpanel::FileUtils::Read::for_each_directory_node(
        $htpasswds_dir,
        $htpasswds_cr,
    );

    return 1;
}

sub _chown {
    my ( $warnings_ar, $uid, $gid, @paths ) = @_;

    local $!;

    chown( $uid, $gid, @paths ) or do {
        push @$warnings_ar, Cpanel::Exception::create( 'IO::ChownError', [ path => \@paths, uid => $uid, gid => $gid, error => $! ] );
    };

    return;
}

sub _chmod {
    my ( $warnings_ar, $perms, @paths ) = @_;

    local $!;

    chmod( $perms, @paths ) or do {
        push @$warnings_ar, Cpanel::Exception::create( 'IO::ChmodError', [ path => \@paths, permissions => $perms, error => $! ] );
    };

    return;
}

1;
