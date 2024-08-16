package Whostmgr::Transfers::SystemsBase::EA4;

# cpanel - Whostmgr/Transfers/SystemsBase/EA4.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::Transfers::SystemsBase::EA4

=head1 SYNOPSIS

    package Whostmgr::Transfers::Systems::NewSubsystem;

    use base qw(
      Whostmgr::Transfers::Systems
      Whostmgr::Transfers::SystemsBase::EA4
    );

    if ( $self->was_using_ea4() ) {
        $self->is_php_version_installed('ea-php12345');
    }

    1;

=head1 DESCRIPTION

This module adds EasyApache4 handling into the WHM transfer system.
There is functionality for both userdata validation, and .htaccess
modification.

=cut

use strict;
use warnings;

use Path::Iter                           ();
use File::Basename                       ();
use Cpanel::CachedDataStore              ();
use Cpanel::Config::Httpd::EA4           ();
use Cpanel::Config::userdata::Constants  ();
use Cpanel::Config::userdata::Cache      ();
use Cpanel::Config::WebVhosts            ();
use Cpanel::Exception                    ();
use Cpanel::ProgLang                     ();
use Cpanel::ProgLang::Conf               ();
use Cpanel::WebServer                    ();
use Cpanel::AccessIds::ReducedPrivileges ();

use constant {
    FIELD_DOCROOT     => $Cpanel::Config::userdata::Cache::FIELD_DOCROOT,
    FIELD_DOMAIN_TYPE => $Cpanel::Config::userdata::Cache::FIELD_DOMAIN_TYPE,
};

=head1 VARIABLES

=head2 B<$PHPS>

A local cache of the installed versions of PHP, since retrieval may be
an expensive operation.

=cut

# 'our' instead of 'my' so we can fool with it in testing.
our $PHPS;

=head1 METHODS

=head2 B<was_using_ea4()>

Check whether the old server was running EasyApache4, by checking the
old userdata for the 'phpversion' parameter.

=head3 B<Returns>

1 if the userdata looks like it was from an EA4 host, 0 if not.

=cut

sub was_using_ea4 {
    my ($self) = @_;

    # Look for any phpversion keys in the userdata files
    my $dir = $self->extractdir();
    $dir .= '/userdata';
    return 0 unless -d $dir;

    my $was_using_ea4 = 0;
    my $fetch         = Path::Iter::get_iterator($dir);
    my $next_path;    # buffer; minor optimization
    while ( $next_path = $fetch->() ) {
        next if -d $next_path;

        if ( open my $fh, '<', $next_path ) {
            if ( grep m/\Aphpversion:/, <$fh> ) {
                close $fh;
                $was_using_ea4 = 1;
                last;
            }
            close $fh;
        }    # the previous version of this function (see ZC-2239) silently ignored files that could not be opened so we do not do something lik    e:
             # else {
             #     warn "Could not open “$next_path” for reading: $!\n";
             # }
    }

    return $was_using_ea4;
}

=head2 B<is_php_version_installed($version)>

Checks the destination system for the supplied PHP version.

=over 4

=item B<$version> [in]

The PHP version to check for installation

=back

=head3 B<Returns>

1 if the supplied PHP version is installed, 0 if not.

=head3 B<Notes>

If we have any trouble fetching the installed list, we will emit a
warning, and assume that no PHPs are installed.

=cut

sub is_php_version_installed {
    my ( $self, $version ) = @_;

    return 0 unless Cpanel::Config::Httpd::EA4::is_ea4() and defined $version;

    unless ( defined $PHPS ) {
        local $@;
        eval { $PHPS = $self->_proglang_php()->get_installed_packages(); };
        if ( my $ex = $@ ) {

            # If we can't retrieve them, we'll just cache an empty
            # list, so we don't get this same warning EVERY TIME.
            $PHPS = [];
            $self->warn( $self->_locale()->maketext( 'Cannot retrieve installed [asis,PHP] versions: [_1]', Cpanel::Exception::get_string($ex) ) );
        }
    }
    return grep( /\A\Q$version\E\Z/, @$PHPS ) ? 1 : 0;
}

=head2 B<normalize_userdata_ea4_phpversion($userdata)>

Takes a set of userdata for a vhost, and modifies it according to the
installed versions of PHP on the destination system.

=over 4

=item B<$userdata> [in,out]

A hashref of the userdata for a virtual host.  It may be modified by
this method.

=back

=head3 B<Returns>

Nothing.  The userdata we receive is modified in place.

=cut

sub normalize_userdata_ea4_phpversion {
    my ( $self, $userdata ) = @_;

    if ( Cpanel::Config::Httpd::EA4::is_ea4() ) {
        if (   !$self->is_php_version_installed( $userdata->{'phpversion'} )
            && defined( $userdata->{'phpversion'} )
            && $userdata->{'phpversion'} ne 'inherit' ) {
            $self->warn( $self->_locale()->maketext( "Set [asis,EasyApache4] [asis,PHP] version for domain “[_1]” to “[_2]” because version “[_3]” is not installed.", $userdata->{'servername'}, 'inherit', $userdata->{'phpversion'} ) );
            $userdata->{'phpversion'} = 'inherit';
        }
    }
    elsif ( defined $userdata->{'phpversion'} ) {
        $self->warn( $self->_locale()->maketext( 'Removed [asis,EasyApache4] [asis,PHP] version setting from domain “[_1]”.', $userdata->{'servername'} ) );
        delete $userdata->{'phpversion'};
    }
    return;
}

=head2 B<vhost_userdata_path_for_docroot($docroot)>

Retrieves the virtual host userdata filename for a given document
root, if any.

=over 4

=item B<$docroot> [in]

The directory we wish to check

=back

=head3 B<Returns>

The full path of the userdata file which corresponds to the document
root we received.  Undef if there is no corresponding userdata.

=cut

my %_domain_types_that_have_docroot = ( 'main' => 1, 'sub' => 1 );

sub vhost_userdata_path_for_docroot {
    my ( $self, $docroot ) = @_;
    if ( !$self->{'_docroot_to_vhost_map'} ) {

        my $cache = Cpanel::Config::userdata::Cache::load_cache( $self->newuser() );
        $self->{'_docroot_to_vhost_map'} = { map { $_domain_types_that_have_docroot{ $cache->{$_}->[FIELD_DOMAIN_TYPE] } ? ( $cache->{$_}->[FIELD_DOCROOT] => $_ ) : () } keys %$cache };
    }
    if ( $self->{'_docroot_to_vhost_map'}->{$docroot} ) {
        return "$Cpanel::Config::userdata::Constants::USERDATA_DIR/" . $self->newuser() . "/" . $self->{'_docroot_to_vhost_map'}->{$docroot};
    }
    return;
}

=head2 B<version_from_vhost_file($vhost_file)>

Retrieve the configured PHP version from a userdata file.

=over 4

=item B<$vhost_file> [in]

The pathname of the userdata file we wish to search

=back

=head3 B<Returns>

The configured PHP version for the given userdata file.  Undef if
either the file doesn't exist, or if no PHP version was found in the
file.

=cut

sub version_from_vhost_file {
    my ( $self, $vhost ) = @_;

    return unless $vhost;

    my $vhost_data = Cpanel::CachedDataStore::fetch_ref($vhost);
    return $vhost_data->{'phpversion'} || undef;
}

=head2 B<repair_ea4_in_htaccess($htaccess)>

Normalize an .htaccess file to match the userdata we find on the
system.  If we have no EA4 userdata, we'll strip any .htaccess
modifications.  If we do have a valid PHP version setting, we'll add
it as normal for EasyApache4.  In the case that the .htaccess file
does not correspond with any virtual host, we'll remove any recognized
PHP version block.

=over 4

=item B<$htaccess> [in]

Pathname of an .htaccess file to check/modify

=back

=head3 B<Returns>

Nothing.

=cut

sub _ws_obj {
    my ($self) = @_;
    return $self->{'_ws_obj'} if $self->{'_ws_obj'};
    $self->{'_ws_obj'} = Cpanel::WebServer->new();
    my $user = $self->newuser();
    $self->{'_ws_obj'}->get_server( type => 'apache' )->make_htaccess( user => $user );    # Do not remove this, see ZC-1332
    return $self->{'_ws_obj'};
}

sub _webvhosts_obj {
    my ($self) = @_;
    return ( $self->{'_webvhosts_obj'} ||= Cpanel::Config::WebVhosts->load( $self->newuser ) );
}

sub _proglang_php_conf {
    my ($self) = @_;

    return $self->{'_prolang_php_conf'} if $self->{'_prolang_php_conf'};
    my $php = $self->_proglang_php() or return;
    return ( $self->{'_prolang_php_conf'} = Cpanel::ProgLang::Conf->new( type => $php->type() ) );
}

sub _proglang_php {
    my ($self) = @_;

    return $self->{'_prolang_php'} if $self->{'_prolang_php'};

    # This block should run as root
    die "_proglang_php: Must run as root" if $>;
    my $php = eval { Cpanel::ProgLang->new( type => "php" ) };
    if ( !$php ) {
        $self->warn($@);
        return;
    }
    return ( $self->{'_prolang_php'} = $php );
}

sub repair_ea4_in_htaccess {
    my ( $self, $htaccess ) = @_;

    my $docroot = $htaccess;
    $docroot =~ s~/.htaccess\z~~;

    my $user = $self->newuser();
    $self->out( $self->_locale()->maketext( "Repairing “[_1]” for [asis,EasyApache 4] …", $htaccess ) );

    my $vhost_userdata_path = $self->vhost_userdata_path_for_docroot($docroot) or do {
        $self->out( $self->_locale()->maketext( "The [asis,htaccess] file “[_1]” is not in a document root …", $htaccess ) );
        return;
    };

    # If the directory is a vhost docroot, *and* there's a
    # version set in the vhost's userdata, *and* that version
    # is installed, then the vhost *should* be valid.
    # Otherwise, do nothing, because this vhost is already
    # configured correctly.
    my $version = $self->version_from_vhost_file($vhost_userdata_path) or return 1;

    local $@;
    my $pconf = eval { $self->_proglang_php_conf() } or return;
    my $htype = $pconf->get_package_info( package => $version );

    my $phpfpm_vhost = $self->_find_phpfpm_domain_for_vhost( File::Basename::basename($vhost_userdata_path) );
    $self->out( $self->_locale()->maketext( "The system mapped “[_1]” to the virtual host “[_2]” …", $htaccess, $phpfpm_vhost ) );
    my @set_vhost_lang_package_base_args = (
        user                         => $user,
        vhost                        => $phpfpm_vhost,
        lang                         => scalar $self->_proglang_php(),
        'skip_userdata_cache_update' => 1                                # We will do this at the end anyways
    );

    eval {
        if ( Cpanel::Config::Httpd::EA4::is_ea4() ) {
            my $ws = $self->_ws_obj();
            if ( !$htype ) {
                $ws->set_vhost_lang_package( @set_vhost_lang_package_base_args, package => 'inherit' );
            }
            else {
                # TODO: handle when $htype is not available on this box

                if ( $self->is_php_version_installed($version) ) {

                    # Redo the existing handler block, in case it's different on this server.
                    $ws->set_vhost_lang_package( @set_vhost_lang_package_base_args, package => $version );
                }
                else {
                    $self->warn("$version is not installed on this server, falling back to inherit …");
                    $ws->set_vhost_lang_package( @set_vhost_lang_package_base_args, package => 'inherit' );
                }
            }
        }
        else {
            # This block should run as the user
            my $privs = Cpanel::AccessIds::ReducedPrivileges->new($user);
            _strip_ea4_from_htaccess($htaccess);
        }
    };
    if ( my $ex = $@ ) {
        if ( eval { $ex->isa('Cpanel::Exception') } ) {
            $self->warn( $self->_locale()->maketext( 'Could not update “[_1]”: [_2]', $htaccess, $ex->get_string() ) );
        }
        else {
            $self->warn($ex);
        }
    }
    return;
}

sub _strip_ea4_from_htaccess {
    my ($htaccess) = @_;

    # This code is adapted from Cpanel::WebServer::Supported::apache::Htaccess, whose
    # interface can't work with EA3 systems.
    #
    # This is necessary because it's not possible for Transfer Tool to modify .htaccess files
    # in-flight, so if an account is transferred from an EA4 system to an EA3 system AND has
    # multi-php selections, it will still have EA4-specific .htaccess directives, and PHP
    # will not function.
    #
    # When the last version of cPanel & WHM to support EA3 passes its EOL, this code should
    # go away.

    require Cpanel::Exception;
    require Cpanel::Fcntl;
    require Cpanel::WebServer::Supported::apache::Htaccess;

    my $BEGIN_TAG = $Cpanel::WebServer::Supported::apache::Htaccess::BEGIN_TAG;
    my $COMMENTS  = $Cpanel::WebServer::Supported::apache::Htaccess::COMMENTS;
    my $END_TAG   = $Cpanel::WebServer::Supported::apache::Htaccess::END_TAG;

    sysopen my $fh, $htaccess, Cpanel::Fcntl::or_flags(qw( O_RDWR O_NOFOLLOW O_CREAT ))
      or die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $htaccess, error => $!, mode => '+<' ] );

    my $contents;

    {
        local $/ = undef;
        $contents = <$fh>;
    }

    # We're already assuming $type = 'php', in case you're wondering where $type went.
    # We can't actually derive it from anything since that interface doesn't work on EA3
    # systems anymore.
    $contents =~ s{ ($COMMENTS\#\s*php\s*--\s*\Q$BEGIN_TAG\E
                    .*?
                    \#\s*php\s*--\s*\Q$END_TAG\E) }{}isxg;

    seek( $fh, 0, 0 );
    print {$fh} $contents;

    # We don't want to die on a failed truncate, because truncate may not be a valid
    # operation if we're making a new file.
    truncate( $fh, tell($fh) );

    close $fh
      or die Cpanel::Exception::create( 'IO::FileCloseError', [ path => $htaccess, error => $! ] );

    return;
}

sub _find_phpfpm_domain_for_vhost {
    my ( $self, $vhost ) = @_;

    my $web_vhost_obj = $self->_webvhosts_obj() or do {
        my $user = $self->newuser();
        die "Failed to load web vhosts for user “$user”";
    };

    my $subdomains_to_addons_map_hr = $web_vhost_obj->subdomains_to_addons_map();
    if ( $subdomains_to_addons_map_hr->{$vhost} ) {

        # PHP-FPM stores its configuration for addon domains as the name of the addon domain
        # this should look up the addon domain and make $fpm_domain the value of the addon domain
        # rather than the subdomain.
        #
        # Limitation:
        # It’s possible via the API (not the UI) to park additional domains on top of the underlying
        # subdomain that an addon domain is using. In this case we are chosing the first parked domain
        # we see in the map.  While this has not been a problem in practice, a better solution will
        # be needed in the future.
        #
        # This will eventually be passed to Cpanel::PHPFPM::Get::get_php_fpm
        # in Cpanel::WebServer::Supported::apache.pm::set_vhost_lang_package()
        #

        return $subdomains_to_addons_map_hr->{$vhost}->[0];
    }
    return $vhost;
}

1;
