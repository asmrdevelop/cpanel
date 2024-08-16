package Cpanel::Htaccess;

# cpanel - Cpanel/Htaccess.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 MODULE

C<Cpanel::Htaccess>

=head1 DESCRIPTION

C<Cpanel::Htaccess> provides implementation methods for various .htaccess based
features such as password protected directories, leech protected directories,
indexing of directories and similar.

This file also include the earlier api1 calls for these applications.

=cut

use Cpanel ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Autodie ();

use Cpanel::Imports;

use Cpanel::Exception                   ();
use Cpanel::CheckPass::AP               ();
use Cpanel::Config::LoadCpConf          ();
use Cpanel::Encoder::Tiny               ();
use Cpanel::Encoder::URI                ();
use Cpanel::FileUtils::Equiv            ();
use Cpanel::FileUtils::Move             ();
use Cpanel::FileUtils::Read             ();
use Cpanel::HttpUtils::Htaccess         ();
use Cpanel::HttpUtils::Htpasswd         ();
use Cpanel::Logger                      ();
use Cpanel::Rand::Get                   ();
use Cpanel::SafeDir                     ();
use Cpanel::SafeDir::MK                 ();
use Cpanel::SafeFile                    ();
use Cpanel::SafeRun::Errors             ();
use Cpanel::DirectoryIndexes::IndexType ();

use Errno qw[ENOENT];

my $logger = Cpanel::Logger->new();

our $VERSION = '1.3';

sub Htaccess_init { }

=head1 FUNCTIONS

=head2 _ensure_dir(DIR) [PRIVATE]

Validates the pass in directory is usable.

=cut

sub _ensure_dir {
    my $dir = shift;
    if ( !defined $dir ) {
        die "Missing parameter 'dir'";
    }
    elsif ( $dir eq '' ) {
        die "Invalid directory: $dir";
    }
    else {
        undef $!;
        die "Unable to access directory $dir! You do not seem to have permission to access this directory. $!"
          if !-x $dir || !-r _;
    }
    return;
}

=head3 _safe_dir(DIR) [PRIVATE]

Helper method to limit the user to directories that are safe to manage.

=cut

sub _safe_dir {
    my $path = shift;
    my $dir  = Cpanel::SafeDir::safedir($path);
    $dir =~ s{/+}{/}g;    # remove repeated /
    $dir =~ s{/$}{}g;     # remove trailing /

    # safedir does some unexpected things currently, making this painful.
    # it returns $Cpanel::abshomdir for symlinks
    # it expands / to the homedir also
    if ( $dir eq $Cpanel::abshomedir && $dir ne $path && $path ne '/' ) {
        die( locale()->maketext( "“[_1]” Does not appear to be a valid path.", $path ) );
    }

    # Run a few sanity checks
    stat $dir or do {
        die locale()->maketext( '“[_1]” does not exist.', $path ) . "\n" if $!{'ENOENT'};
        die locale()->maketext( 'Failed to discover if “[_1]” exists: [_2]', $path, $! ) . "\n";
    };
    if ( !-d _ ) {
        die locale()->maketext( '“[_1]” is not a directory.', $path ) . "\n";
    }
    if ( !-x _ ) {
        die locale()->maketext( 'Directory “[_1]” does not have the execute permissions.', $path ) . "\n";
    }

    return $dir;
}

=head2 _virtual_dir(DIR) [PRIVATE]

Trim out the users home folder and leading / from directory.

These virtual directories are used in various storage systems.

=head3 ARGUMENTS

=over

=item DIR - string

Full path to the desired directory you want to calculate the virtual directory for.

=back

=head3 RETURNS

string - relative directory from the users home directory

=cut

sub _virtual_dir {
    my $vdir = shift;
    my $rdir = $vdir =~ s/^\Q${Cpanel::homedir}\E([\/]+)//r;

    return ($1) ? $rdir : $vdir;
}

=head2 _get_default_authname(DIR) [PRIVATE]

Generate a authname when its not provided by the user.

=cut

sub _get_default_authname {
    my ($dir) = @_;
    my $vdir = _virtual_dir($dir);
    return "Protected '$vdir'";
}

=head3 _upgrade_passwd_file_location(DIR)

Relocate any .htpasswd files located in the requested directory
to the new location in /home/<user>/.htpasswds/<directories ...>/passwd

This new location will never be served by the web server and also helps
keep people from accidentally deleting them in file manager or via FTP or
WEBDAV since they are in a hidden folder in the users home directory.

=head3 RETURNS

The updated password protected information similar to how
C<Cpanel::HttpUtils::Htaccess::get_protected_directives> retrieves the
same data.

=cut

sub _upgrade_passwd_file_location {
    my ($dir) = @_;

    my $passwd_file_dir = Cpanel::HttpUtils::Htpasswd::get_path($dir);

    my $info = Cpanel::HttpUtils::Htaccess::get_protected_directives($dir);
    if ( $info->{protected} ) {
        my $changed              = 0;
        my $legacy_htpasswd_path = "$dir/.htpasswd";
        $legacy_htpasswd_path =~ s{/+}{/}g;
        my $modern_htpasswd_path = "$passwd_file_dir/passwd";
        $modern_htpasswd_path =~ s{/+}{/}g;

        # Move the legacy password file if needed
        if ( -e $legacy_htpasswd_path ) {
            if (  !$info->{passwd_file}
                || $info->{passwd_file} eq $legacy_htpasswd_path
                || !Cpanel::FileUtils::Equiv::equivalent_files( $info->{passwd_file}, $legacy_htpasswd_path ) ) {

                # Move htpasswd file from the directory to the "protected" area
                Cpanel::FileUtils::Move::safemv( '-f', $legacy_htpasswd_path, $modern_htpasswd_path );
                $changed = 1;
            }
        }

        # Update the .htaccess file
        if ( !$info->{auth_name} ) {
            $info->{auth_name} = _get_default_authname($dir);
            $changed = 1;
        }

        if ( !$info->{passwd_file} || $changed ) {
            $info->{passwd_file} = $modern_htpasswd_path;
            $changed = 1;
        }

        if ($changed) {
            return Cpanel::HttpUtils::Htaccess::update_protected_directives( $dir, $info );
        }
    }
    return $info;
}

=head2 is_protected(DIR)

Fetches the current protected status of the directory.

=head3 RETURNS

Hashref with the following properties:

=over

=item auth_type - string

Type of authentication. Currently will only be: Basic

=item auth_name - string

Name used for the resource

=item passwd_file - string

Path to the password file on disk

=item protected - Boolean

1 if protected, 0 if not protected.

=back

=cut

sub is_protected {
    my $dir = _safe_dir(shift);
    _ensure_dir($dir);
    _upgrade_passwd_file_location($dir);

    return Cpanel::HttpUtils::Htaccess::get_protected_directives($dir);
}

=head2 _get_parent_dir(DIR) [PRIVATE]

Given a directory, calculate its parent. It will not leave the users home folder.

=head3 ARGUMENTS

=over

=item DIR - string

Directory you want to calculate the parent directory for.

=back

=head3 RETURNS

string - parent directory or same folder if the dir is already the users home directory.

=cut

sub _get_parent_dir {
    my $dir = shift;

    my $vdir = _virtual_dir( $dir . ( $dir !~ /\/\z/ ? '/' : '' ) );
    my @dirs = split( /\//, $vdir );
    return $dir if !@dirs;
    pop @dirs;
    my $remaining = join( '/', @dirs );
    return $Cpanel::homedir . ( $remaining ? '/' . $remaining : '' );
}

=head2 set_protected(DIR, ENABLED, AUTHNAME)

Enable or disable directory protection.

=head3 ARGUMENTS

=over

=item DIR - string

Directory you want to change the protection for.

=item ENABLED - Boolean

1 to enable protection, 0 to disable protection.

=item AUTHNAME - string

Optional resource name to use the AuthName directive for this folder. This name may be
presented by some clients when showing the Basic Authentication popup and is also sometimes
used as the name of the secured resource in password caches. Some clients may ignore this
data when present. If not provided by the caller, this will be auto populated.

=back

=head3 RETURNS

Hashref with the following properties:

=over

=item auth_type - string

Type of authentication. Currently will only be: Basic

=item auth_name - string

Name used for the resource

=item passwd_file - string

Path to the password file on disk

=item protected - Boolean

1 if protected, 0 if not protected.

=back

=cut

sub set_protected {
    my ( $dir, $enabled, $authname ) = @_;
    $dir = _safe_dir($dir);
    _ensure_dir($dir);
    _upgrade_passwd_file_location($dir);

    require Cpanel::Validate::Boolean;
    Cpanel::Validate::Boolean::validate_or_die($enabled);

    $enabled = int($enabled);
    if ( $enabled && !$authname ) {
        $authname = _get_default_authname($dir);
    }

    # Get the current information about the directory
    my $info = Cpanel::HttpUtils::Htaccess::get_protected_directives($dir);

    $info->{protected} = $enabled;
    $info->{auth_name} = $authname;
    if ( !$info->{passwd_file} ) {
        my $htpasswd_directory = Cpanel::HttpUtils::Htpasswd::get_path($dir);
        $info->{passwd_file} = "$htpasswd_directory/passwd";
        $info->{passwd_file} =~ s{//}{/};    # clean up cruft
    }

    return Cpanel::HttpUtils::Htaccess::set_protected_directives( $dir, $info );
}

=head2 list_directories(DIR, OPTS)

=head3 ARGUMENTS

=over

=item DIR - string

Directory you want to change the protection for.

=item OPTS - hash

With any of the following options

=over

=item directory_privacy - Boolean

Check if the directory uses password protection.

=item leech_protection - Boolean

Check if the directory has leech protection enabled.

=item directory_indexed - Boolean

Check if directory indexing is enabled.

=back

To select data from multiple sub-systems, you can combine them.

=back

=head3 RETURNS

=over

=item home - hashref

Information about the users home directory on the server.

=over

=item path - string

The path on disk.

=item state - hashref

=over

=item error - string

Only present if the state could not be retrieved.

=item auth_type - string

Only present when requested type is 0. Type of authentication. Currently will only be: Basic

=item auth_name - string

Only present when requested type is 0. Name used for the resource

=item passwd_file - string

Only present when requested type is 0. Path to the password file on disk

=item protected - Boolean

Only present when requested type is 0. 1 if protected, 0 if not protected.

TODO: Add others once we get to them.

=back

=back

=item parent - hashref

Information about the parent of the current path if not the home directory

=over

=item path - string

The path on disk.

=item state - hashref

=over

=item error - string

Only present if the state could not be retrieved.

=item auth_type - string

Only present when requested type is 0. Type of authentication. Currently will only be: Basic

=item auth_name - string

Only present when requested type is 0. Name used for the resource

=item passwd_file - string

Only present when requested type is 0. Path to the password file on disk

=item protected - Boolean

Only present when requested type is 0. 1 if protected, 0 if not protected.

TODO: Add others once we get to them.

=back

=back

=item current - hashref

The currently selected folder.

=over

=item path - string

What the path to the home folder is on disk.

=item state - hashref

=over

=item error - string

Only present if the state could not be retrieved.

=item auth_type - string

Only present when requested type is 0. Type of authentication. Currently will only be: Basic

=item auth_name - string

Only present when requested type is 0. Name used for the resource

=item passwd_file - string

Only present when requested type is 0. Path to the password file on disk

=item protected - Boolean

Only present when requested type is 0. 1 if protected, 0 if not protected.

TODO: Add others once we get to them.

=back

=back

=item children - array

List of child folders and their state. State varies by type requested. Each item is a hashref with the following properties

=item path - string

The path on disk.

=item state - hashref

=over

=item error - string

Only present if the state could not be retrieved.

=item auth_type - string

Only present when requested type is 0. Type of authentication. Currently will only be: Basic

=item auth_name - string

Only present when requested type is 0. Name used for the resource

=item passwd_file - string

Only present when requested type is 0. Path to the password file on disk

=item protected - Boolean

Only present when requested type is 0. 1 if protected, 0 if not protected.

=back

=back

=cut

sub list_directories {
    my ( $dir_in, %opts ) = @_;
    my $dir = _safe_dir($dir_in);
    if ( !keys %opts ) {
        $opts{directory_privacy} = 1;
    }

    foreach my $key ( keys %opts ) {
        if ( !grep { $key eq $_ } qw(uapi directory_privacy leech_protection directory_indexed) ) {
            die locale()->maketext( 'The system did not recognize the directory list type “[_1]” that you requested.', $key );
        }
    }

    _ensure_dir($dir);
    _upgrade_passwd_file_location($dir);

    my @children;

    Cpanel::FileUtils::Read::for_each_directory_node(
        $dir,
        sub {

            my $path = $_;

            return if $path =~ m/^[.]+/;    # hide dotfiles
            return if -l "$dir/$path";      # hide links
            return if !-d "$dir/$path";     # hide files

            push @children, {
                path  => "$dir/$path",
                state => get_directory_state( "$dir/$path", %opts ),
            };
        }
    );

    my $parent = _get_parent_dir($dir);

    @children = sort { $a->{path} cmp $b->{path} } @children;
    my $data = {
        home => {
            path  => $Cpanel::homedir,
            state => get_directory_state( $Cpanel::homedir, %opts ),
        },
        parent => {
            path  => $parent,
            state => get_directory_state( $parent, %opts ),
        },
        current => {
            path  => $dir,
            state => get_directory_state( $dir, %opts ),
        },
        children => \@children,
    };

    return $data;
}

my %state_cache;

=head2 get_directory_state(DIR, WHICH)

=head3 ARGUMENTS

=over

=item DIR - string

Path to the directory

=item WHICH - hash

Use any of the following options:

=over

=item uapi - Boolean

When true, use the UAPI mode, otherwise use the default.

=item directory_privacy - Boolean

Check if the directory uses password protection.

=item leech_protection - Boolean

Check if the directory has leech protection enabled.

=item directory_indexed - Boolean

Check if directory indexing is enabled.

=back

=back

=head3 RETURNS

Varies depending on the type requested.

=over

=item When directory_privacy is true.

=over

=item error - string

Only present if the state could not be retrieved.

=item auth_type - string

Type of authentication. Currently will only be: Basic

=item auth_name - string

Name used for the resource

=item passwd_file - string

Path to the password file on disk

=item protected - Boolean

1 if protected, 0 if not protected.

=back

=item When directory_indexed is true.

=over

=item error - string

Only present if the state could not be retrieved.

=item index_type - string

One of the following: inherit, disabled, standard, fancy

=back

=item When leech_protection is true.

=over

=over

=item error - string

Only present if the state could not be retrieved.

=item has_leech_protection - integer

An integer representing the state of leech protection where 0 = off and 1 = on.

=back

=back

=back

=cut

sub get_directory_state {
    my ( $dir, %which ) = @_;
    my $state = $state_cache{$dir} || {};

    if ( $which{directory_privacy} && !exists $state->{protected} ) {
        my $response = eval { is_protected($dir) };
        if ( my $exception = $@ ) {
            $state->{error} = $exception;
        }
        else {
            $state = {
                %$state,
                %$response,
            };
        }
    }

    if ( $which{leech_protection} && !exists $state->{has_leech_protection} ) {
        my $response = eval { has_leech_protection($dir); };
        if ( my $exception = $@ ) {
            $state->{error} = $exception->isa('Cpanel::Exception') ? $exception->get_string_no_id() : $exception;
        }
        else {
            $state->{has_leech_protection} = $response;
        }
    }

    if ( $which{directory_indexed} && !exists $state->{index_type} ) {
        my $response = eval {
            my $type = Cpanel::Htaccess::indextype( $dir, uapi => $which{uapi} );
            Cpanel::DirectoryIndexes::IndexType::internal_to_external($type);
        };
        if ( my $exception = $@ ) {
            $state->{error} = $exception;
        }
        else {
            $state->{index_type} = $response;
        }
    }

    $state_cache{$dir} = $state;

    return $state;
}

sub htdirls {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $dir, $listtype ) = @_;
    return if !main::hasfeature('webprotect');

    my $original_html_safe_dir = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    $dir = $Cpanel::homedir if !$dir;
    my $rDIRCFG = _htaccess_dir_setup($dir);
    $dir = $rDIRCFG->{'dir'};
    my $html_safe_dir = $rDIRCFG->{'html_safe_dir'};
    my $uri_safe_dir  = $rDIRCFG->{'uri_safe_dir'};

    undef $!;
    if ( !defined $dir || $dir eq '' || !chdir $dir ) {
        print "<br />Unable to change directory to $original_html_safe_dir! You do not seem to have permission to access this directory! " . ( $! ? "(System Error: $!)" : '' ) . "<br /><br />\n";
        return;
    }

    my $vdir = $dir;
    $vdir =~ s/^$Cpanel::homedir//g;
    $vdir =~ s/^[\s\+\/]*//g;

    my $html_safe_vdir = Cpanel::Encoder::Tiny::safe_html_encode_str($vdir);
    my $uri_safe_vdir  = Cpanel::Encoder::URI::uri_encode_str($vdir);

    my $script_uri       = $ENV{'SCRIPT_URI'};
    my $uri_safe_homedir = Cpanel::Encoder::URI::uri_encode_str($Cpanel::homedir);
    my @DIRS             = split( /\//, $vdir );

    if ( $#DIRS == -1 ) {
        print <<"EOM";
<b><a href="$script_uri?dir=$uri_safe_homedir"><i class="far fa-folder fa-lg" aria-hidden="true"></i></a> <a href="dohtaccess.html?dir=$uri_safe_homedir">/</a></b>
EOM
    }
    else {
        print <<"EOM";
<b><a href="$script_uri?dir=$uri_safe_dir"><i class="far fa-folder fa-lg" aria-hidden="true"></i><a href="$ENV{'SCRIPT_URI'}">/</a></b>
EOM
    }
    my $tdir;
    foreach my $dirs (@DIRS) {
        $tdir = $tdir . "$dirs/";
        my $html_safe_dirs = Cpanel::Encoder::Tiny::safe_html_encode_str($dirs);
        my $uri_safe_tdir  = Cpanel::Encoder::URI::uri_encode_str($tdir);
        if ( $dirs eq $DIRS[$#DIRS] ) {
            print <<"EOM";
<a href="dohtaccess.html?dir=$uri_safe_homedir%2F$uri_safe_tdir">$html_safe_dirs</a> /
EOM
        }
        else {
            print <<"EOM";
<a href="$script_uri?dir=$uri_safe_homedir%2F$uri_safe_tdir">$html_safe_dirs</a> /
EOM
        }
    }
    print <<'EOM';
<i>(Current Folder)</i>
<br />
EOM

    if ( $dir ne $Cpanel::homedir ) {
        my @DIRS = split( /\//, $dir );
        my $n    = 0;
        my $topdir;
        foreach my $dirs (@DIRS) {
            if ( !( $#DIRS == $n ) ) {
                $topdir = $topdir . $dirs . '/';
            }
            $n++;
        }
        my $uri_safe_topdir = Cpanel::Encoder::URI::uri_encode_str($topdir);
        print <<"EOM";
<a href="$script_uri?dir=$uri_safe_topdir\"><i class="far fa-folder fa-lg" aria-hidden="true"></i></a> <a href="$script_uri?dir=$uri_safe_topdir"><b>Up One Level</b></a>
<br />
EOM
    }

    if ( opendir my $curdir_dh, '.' ) {
        my @DIRLS = readdir $curdir_dh;
        closedir $curdir_dh;

      DIRLOOP:
        foreach my $file ( sort @DIRLS ) {
            next DIRLOOP if $file =~ m/^[.]+/;    #hide dotfiles
            next DIRLOOP if -l $file || !-d _;

            my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
            my $uri_safe_file  = Cpanel::Encoder::URI::uri_encode_str($file);

            if ( $listtype == 1 ) {
                my $indextype = indextype("$dir/$file");
                if ( $indextype == 0 ) {
                    print qq{<i class="fas fa-ban fa-lg" aria-hidden="true"></i>};
                }
                print qq{<a href="$script_uri?dir=${uri_safe_dir}%2F${uri_safe_file}"><i class="far fa-folder fa-lg" aria-hidden="true"></i></a> <a href="dohtaccess.html?dir=$uri_safe_dir%2F$uri_safe_file">$html_safe_file</a><br />};
            }
            elsif ( $listtype == 2 ) {
                if ( hasleech("${dir}/${file}") ) {
                    print qq{<i class="fas fa-shield-alt fa-lg" aria-hidden="true"></i> };
                }
                print qq{<a href="$script_uri?dir=${uri_safe_dir}%2F${uri_safe_file}"><i class="far fa-folder fa-lg" aria-hidden="true"></i></a> <a href="dohtaccess.html?dir=$uri_safe_dir%2F$uri_safe_file">$html_safe_file</a><br />};
            }
            else {
                my $isprotected = 0;
                if ( -e "$dir/$file/.htaccess" ) {
                    if ( open my $ht_fh, '<', "$dir/$file/.htaccess" ) {
                        while (<$ht_fh>) {
                            if (m/require valid-user/i) { $isprotected = 1; }
                        }
                        close $ht_fh;
                    }
                    else {
                        Cpanel::Logger::logger( { 'message' => "Unable to open $dir/$file/.htaccess: $!", 'level' => 'warn', 'server' => __PACKAGE__, 'output' => 0, } );
                    }
                }

                if ($isprotected) {
                    print <<"EOM";
<a href="$script_uri?dir=${uri_safe_dir}%2F${uri_safe_file}"><i class="fas fa-lock fa-lg" aria-hidden="true"></i></a> <a href="dohtaccess.html?dir=$uri_safe_dir%2F$uri_safe_file">$html_safe_file</a>
<br />
EOM
                }
                else {
                    print <<"EOM";
<a href="$script_uri?dir=${uri_safe_dir}%2F${uri_safe_file}"><i class="far fa-folder fa-lg" aria-hidden="true"></i></a> <a href="dohtaccess.html?dir=$uri_safe_dir%2F$uri_safe_file">$html_safe_file</a>
<br />
EOM
                }
            }
        }
    }
    else {
        print "<br />Unable to read current directory! You do not seem to have permission! (System Error: $!)<br /><br />\n";
    }

    return;
}

sub checkprotected {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my $dir     = shift;
    my $checked = 'checked="checked"';
    return if !main::hasfeature('webprotect');

    my $rDIRCFG = _htaccess_dir_setup($dir);
    return if ( !defined $rDIRCFG || !$rDIRCFG->{'dir'} || !$rDIRCFG->{'tdir'} );

    $dir = $rDIRCFG->{'dir'};
    my $tdir = $rDIRCFG->{'tdir'};

    my $resource_name;
    my $passwd_file;
    my $protected = 0;
    my @htaccess;

    if ( -e $dir . '/.htaccess' ) {
        if ( open my $htaccess_fh, '<', $dir . '/.htaccess' ) {
            while ( my $line = readline $htaccess_fh ) {
                chomp $line;
                if ( $line =~ m/^\s*AuthName\s+"?([^"\s]+)/i ) {
                    $resource_name = $1;
                }
                elsif ( $line =~ m/^\s*AuthUserFile\s+"?([^"\s]+)/i ) {
                    $passwd_file = $1;
                }
                elsif ( $line =~ m/^\s*require\s+valid-user/i ) {
                    $protected = 1;
                }
                push @htaccess, $line;
            }
            close $htaccess_fh;
        }
        else {
            Cpanel::Logger::cplog( "Unable to read $dir/.htaccess: $!", 'warn', __PACKAGE__, 1 );
            return;
        }
    }

    return ''       if !$protected;
    return $checked if $Cpanel::CPDATA{'DEMO'} eq '1';

    if ( !-e "$Cpanel::homedir/.htpasswds" ) {
        require Cpanel::Config::Httpd::Perms;
        my $runs_as_user = Cpanel::Config::Httpd::Perms::webserver_runs_as_user(
            ruid2 => 1,
            itk   => 1,
        );
        if ( !Cpanel::SafeDir::MK::safemkdir( "$Cpanel::homedir/.htpasswds", $runs_as_user ? '0750' : '0755' ) ) {
            return $checked;
        }
    }
    if ( !-e "$Cpanel::homedir/.htpasswds/$tdir" ) {
        if ( !Cpanel::SafeDir::MK::safemkdir( "$Cpanel::homedir/.htpasswds/$tdir", '0755' ) ) {
            return $checked;
        }
    }

    # Move local htpasswd file to protected area
    if ( -e $dir . '/.htpasswd' && !Cpanel::FileUtils::Equiv::equivalent_files( $passwd_file, $dir . '/.htpasswd' ) ) {
        if ( open my $local_htpwd_fh, '<', $dir . '/.htpasswd' ) {
            if ( open my $htpwd_fh, '>>', "$Cpanel::homedir/.htpasswds/$tdir/passwd" ) {
                while (<$local_htpwd_fh>) {
                    print {$htpwd_fh} $_;
                }
                close $local_htpwd_fh;
                close $htpwd_fh;
                unlink $dir . '/.htpasswd';
            }
            else {
                Cpanel::Logger::cplog( "Failed to open $Cpanel::homedir/.htpasswds/$tdir/passwd for update: $!", 'warn', __PACKAGE__, 1 );
                return $checked;
            }
        }
        else {
            Cpanel::Logger::cplog( "Failed to open $dir/.htpasswd for update: $!", 'warn', __PACKAGE__, 1 );
        }
    }

    my $needs_update;
    if ( !$resource_name ) {
        @htaccess = grep( !/^\s*AuthName\s+/, @htaccess );
        push @htaccess, qq{AuthName "Protected $tdir"};
        $needs_update = 1;
    }

    if ( !$passwd_file ) {
        $passwd_file = "$Cpanel::homedir/.htpasswds/$tdir/passwd";
        @htaccess    = grep( !/^\s*AuthUserFile\s+/, @htaccess );
        push @htaccess, qq{AuthUserFile "$passwd_file"};
        $needs_update = 1;
    }

    # Move legacy htpasswd file to protected area
    elsif ( $passwd_file !~ m/service\.pwd$/ && !Cpanel::FileUtils::Equiv::equivalent_files( $passwd_file, "$Cpanel::homedir/.htpasswds/$tdir/passwd" ) ) {
        if ( -e $passwd_file ) {
            if ( open my $local_htpwd_fh, '<', $passwd_file ) {
                if ( open my $htpwd_fh, '>>', "$Cpanel::homedir/.htpasswds/$tdir/passwd" ) {
                    while (<$local_htpwd_fh>) {
                        print {$htpwd_fh} $_;
                    }
                    close $local_htpwd_fh;
                    close $htpwd_fh;
                    unlink $passwd_file;
                }
                else {
                    Cpanel::Logger::cplog( "Failed to open $Cpanel::homedir/.htpasswds/$tdir/passwd for update: $!", 'warn', __PACKAGE__, 1 );
                    return $checked;
                }
            }
            else {
                Cpanel::Logger::cplog( "Failed to open $passwd_file for update: $!", 'warn', __PACKAGE__, 1 );
                return $checked;
            }
        }
        @htaccess = grep( !/^\s*AuthUserFile\s+/, @htaccess );
        push @htaccess, qq{AuthUserFile "$Cpanel::homedir/.htpasswds/$tdir/passwd"};
        $needs_update = 1;
    }

    if ($needs_update) {
        if ( open my $htaccess_fh, '>', $dir . '/.htaccess' ) {
            foreach my $line (@htaccess) {
                print {$htaccess_fh} $line . "\n";
            }
            close $htaccess_fh;
        }
    }
    return $checked;
}

sub set_protect {
    my ( $dir, $pval, $resname ) = @_;

    return if !main::hasfeature('webprotect');
    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        print "Sorry, this feature is disabled in demo mode.";
        return;
    }

    $pval = int($pval);

    my $rDIRCFG = _htaccess_dir_setup($dir);
    $dir = $rDIRCFG->{'dir'};
    my $html_safe_dir = $rDIRCFG->{'html_safe_dir'};
    my $uri_safe_dir  = $rDIRCFG->{'uri_safe_dir'};
    my $tdir          = $rDIRCFG->{'tdir'};

    if ( !-e $Cpanel::homedir . '/.htpasswds/' . $tdir ) {
        if ( !Cpanel::SafeDir::MK::safemkdir("$Cpanel::homedir/.htpasswds/$tdir") ) {
            $logger->warn("Failed to create $Cpanel::homedir/.htpasswds/$tdir: $!");
            return;
        }
    }

    my @HT;
    if ( -e $dir . '/.htaccess' ) {
        if ( open( HT, '<', $dir . '/.htaccess' ) ) {
            while (<HT>) {
                chomp;
                push @HT, $_;
            }
            close(HT);
        }
        else {
            $Cpanel::CPERROR{'htaccess'} = 'Failed to open .htaccess for reading.';
            $logger->warn( $Cpanel::CPERROR{'htaccess'} );
            print $Cpanel::CPERROR{'htaccess'};
            return;
        }
    }

    my ( $authuserf, $authname, $passwd_file );

    if ( open( HT, ">", "$dir/.htaccess" ) ) {
        foreach my $line (@HT) {
            if ( $line =~ m/^\s*authuserfile\s+"?([^"\s]+)/i ) {
                $passwd_file = $1;
            }
            elsif ( $line =~ m/^\s*require valid-user/i ) {
                next;
            }
            elsif ( $line =~ m/^\s*authtype/i ) {
                next;
            }
            elsif ( $line =~ m/^\s*authname\s+"?([^"\n]+)/i ) {
                $authname = $1;
                if ( $authname ne $resname ) {
                    $authname = '';
                }
            }
            else {
                print HT $line . "\n";
            }
        }

        if ( !$passwd_file ) {
            $passwd_file = "$Cpanel::homedir/.htpasswds/$tdir/passwd";
        }

        if ($pval) {
            if ( !defined $resname || $resname eq '' ) {
                $resname = 'Restricted Area',;
            }
            print HT "AuthType Basic\n";
            if ( !$authname ) {
                print HT "AuthName \"$resname\"\n";
            }
            if ( !$authuserf ) {
                print HT "AuthUserFile \"$passwd_file\"\n";
            }
            print HT "require valid-user\n";
        }
        close(HT);
    }
    else {
        $Cpanel::CPERROR{'htaccess'} = 'Failed to open .htaccess for writing.';
        $logger->warn( $Cpanel::CPERROR{'htaccess'} );
        print $Cpanel::CPERROR{'htaccess'};
        return;
    }

    ## Touch passwd file
    if ( open my $passwd_fh, '>>', $passwd_file ) {
        close $passwd_fh;
    }
    else {
        print "Failed to create " . Cpanel::Encoder::Tiny::safe_html_encode_str($passwd_file) . ": $!";
    }
    return;
}

sub setphppreference {
    my $php_version = shift;
    my $account     = shift || $Cpanel::user;

    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        print "Sorry, this feature is disabled in demo mode.";
        return;
    }

    if ( $php_version !~ /^\d$/ ) {
        print "Specified PHP version is invalid.";
        return;
    }

    my @command = ( '/usr/local/cpanel/bin/update_php_mime_types', '--user=' . $account );

    if ($php_version) {
        push @command, '--force=' . $php_version;
    }
    else {
        push @command, '--strip';
        push @command, '--recurse=0';
    }
    $Cpanel::CPERROR{'htaccess'} = Cpanel::SafeRun::Errors::saferunallerrors(@command);
    return;
}

sub phpselectable {
    if ( -e apache_paths_facade->dir_conf() . '/php4.htaccess' && -e apache_paths_facade->dir_conf() . '/php5.htaccess' ) {
        $ENV{'php_selectable'} = 1;

        # determine which version is currently selected
        $ENV{'php_selected'} = 0;
        if ( -e $Cpanel::homedir . '/.htaccess' ) {
            if ( open my $htaccess_fh, '<', $Cpanel::homedir . '/.htaccess' ) {
                while ( my $line = readline($htaccess_fh) ) {
                    if ( $line =~ /\s*#\s*Use PHP\s*(\d) as default/ ) {
                        $ENV{'php_selected'} = $1;
                        last;
                    }
                }
                close $htaccess_fh;
            }
        }
    }
    return;
}

sub resname {
    my $dir = shift;

    return if !main::hasfeature('webprotect');
    return if !$dir;
    my $rDIRCFG = _htaccess_dir_setup($dir);
    $dir = $rDIRCFG->{'dir'};

    if ( -e $dir . '/.htaccess' ) {
        if ( open my $ht_fh, '<', $dir . '/.htaccess' ) {
            while (<$ht_fh>) {
                my ( $dirc, $val ) = split( /\s+/, $_, 2 );
                $val  =~ s/\n//g;
                $dirc =~ tr/A-Z/a-z/;
                if ( $dirc =~ m/authname/i ) {
                    $val =~ s/(^\"|\"$)//g;
                    close $ht_fh;
                    return Cpanel::Encoder::Tiny::safe_html_encode_str($val);
                }
            }
            close $ht_fh;
        }
    }
    return;
}

sub api2_listusers {
    my %CFG = @_;
    my @RSD;
    my @USERS = _listusers( $CFG{'dir'} );
    foreach my $user (@USERS) {
        push( @RSD, { 'user' => $user } );
    }
    return @RSD;
}

sub _listusers {
    my $dir = shift;
    return if !main::hasfeature('webprotect');

    my $rDIRCFG = _htaccess_dir_setup($dir);
    return if !defined $rDIRCFG;

    $dir = $rDIRCFG->{'dir'};
    my $html_safe_dir = $rDIRCFG->{'html_safe_dir'};
    my $uri_safe_dir  = $rDIRCFG->{'uri_safe_dir'};
    my $tdir          = $rDIRCFG->{'tdir'};

    if ( !-e "$Cpanel::homedir/.htpasswds/$tdir" ) {
        if ( !Cpanel::SafeDir::MK::safemkdir( "$Cpanel::homedir/.htpasswds/$tdir", '0755' ) ) {
            return;
        }
    }
    my @USERS;
    my $TDP;
    if ( !open( $TDP, '<', "$Cpanel::homedir/.htpasswds/$tdir/passwd" ) ) {
        return @USERS;
    }

    while (<$TDP>) {
        if (/^(\S+):/) {
            push @USERS, $1;
        }
    }
    close($TDP);
    return @USERS;
}

# set the CPVAR{'htaccess_number_of_users'} variable and print the result
sub number_of_users {
    my $dir   = shift;
    my @USERS = _listusers($dir);
    $Cpanel::CPVAR{'htaccess_number_of_users'} = scalar(@USERS);
    print scalar(@USERS);
}

sub showusers {
    my $dir   = shift;
    my @USERS = _listusers($dir);
    foreach my $user (@USERS) {
        my $html_safe_user = Cpanel::Encoder::Tiny::safe_html_encode_str($user);
        print "<option value=\"$html_safe_user\">$html_safe_user</option>\n";
    }
    return;
}

sub set_pass {
    my ( $dir, $user, $pass ) = @_;
    return if !main::hasfeature('webprotect');
    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        print "Sorry, this feature is disabled in demo mode.";
        return;
    }
    my $allownopass = 1;

    $user =~ s/[<>\s]+//g;    # Filter out bad characters
    $dir  =~ s/[<>]+//g;      # Filter out bad characters

    ## phil FIXME: these regex are not doing what we think they are doing. the " & " is taken literally (I think), and Perl does not
    ##   allow a variable length "negative look behind" assertion.
    # remove any ';' that does not follow a &XYZ; HTML encoding so as not to break html encoding...
    #  2: &lt; &gt; 3: &phi; &psi; 4: &bull; &perp; 5: &frasl; &image; 6: &weierp; &#x2118; 7: &epsilon; &alefsym;
    $user =~ s/((?<!\&[#\w]{2}) & (?<!\&[#\w]{3}) & (?<!\&[#\w]{4}) & (?<!\&[#\w]{5}) & (?<!\&[#\w]{6}) & (?<!\&[#\w]{7}))\;//g;
    $dir  =~ s/((?<!\&[#\w]{2}) & (?<!\&[#\w]{3}) & (?<!\&[#\w]{4}) & (?<!\&[#\w]{5}) & (?<!\&[#\w]{6}) & (?<!\&[#\w]{7}))\;//g;

    #$pass =~ s/((?<!\&[#\w]{2}) & (?<!\&[#\w]{3}) & (?<!\&[#\w]{4}) & (?<!\&[#\w]{5}) & (?<!\&[#\w]{6}) & (?<!\&[#\w]{7}))\;//g;

    if ( !$user ) {
        $Cpanel::CPERROR{'htaccess'} = locale()->maketext('The system cannot alter a user without a username.');
        Cpanel::Logger::cplog( $Cpanel::CPERROR{'htaccess'}, 'warn', __PACKAGE__, 1 );
        return;
    }
    if ( !$allownopass && !$pass ) {
        $Cpanel::CPERROR{'htaccess'} = locale()->maketext('The system cannot alter a user without a password.');
        Cpanel::Logger::cplog( $Cpanel::CPERROR{'htaccess'}, 'warn', __PACKAGE__, 1 );
        return;
    }

    my $rDIRCFG = _htaccess_dir_setup($dir);
    $dir = $rDIRCFG->{'dir'};
    my $html_safe_dir = $rDIRCFG->{'html_safe_dir'};
    my $uri_safe_dir  = $rDIRCFG->{'uri_safe_dir'};
    my $tdir          = $rDIRCFG->{'tdir'};

    my $random = Cpanel::Rand::Get::getranddata(256);
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
    my $cpass  = ( !defined( $cpconf->{'use_apache_md5_for_htaccess'} ) || $cpconf->{'use_apache_md5_for_htaccess'} ) ? Cpanel::CheckPass::AP::apache_md5_crypt( $pass, $random ) : crypt( $pass, $random );

    my ($gotuser) = 0;
    Cpanel::SafeDir::MK::safemkdir("$Cpanel::homedir/.htpasswds/$tdir");

    # need to create this either way
    my $passwd  = "$Cpanel::homedir/.htpasswds/$tdir/passwd";
    my $whtlock = Cpanel::SafeFile::safeopen( \*TDPO, ">", "$passwd.tmp" );
    if ( !$whtlock ) {
        print "Could not write to " . Cpanel::Encoder::Tiny::safe_html_encode_str("$passwd.tmp") . "\n";
        return;
    }

    # if the passwd file exists already, read it in and modify to passwd.tmp
    if ( -e $passwd ) {
        my $htlock = Cpanel::SafeFile::safeopen( \*TDP, "<", $passwd );
        if ( !$htlock ) {
            print "Could not read from " . Cpanel::Encoder::Tiny::safe_html_encode_str("$passwd.tmp") . "\n";
            return;
        }
        while (<TDP>) {
            if (/^(\S+):/) {
                if ( $1 eq "$user" ) {
                    $gotuser = 1;
                    print TDPO "$user:$cpass\n";
                }
                else {
                    print TDPO $_;
                }
            }
        }
        Cpanel::SafeFile::safeclose( \*TDP, $htlock );
    }

    # if there was no passwd file or didn't have the user in it already, add it to tmp file
    if ( !($gotuser) ) {
        print TDPO "$user:$cpass\n";
    }
    Cpanel::SafeFile::safeclose( \*TDPO, $whtlock );

    unlink "$Cpanel::homedir/.htpasswds/$tdir/passwd";
    rename "$Cpanel::homedir/.htpasswds/$tdir/passwd.tmp", "$Cpanel::homedir/.htpasswds/$tdir/passwd";

    return "";
}

sub del_user {
    my ( $dir, $user ) = @_;
    return if !main::hasfeature('webprotect');
    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        print "Sorry, this feature is disabled in demo mode.";
        return ();
    }

    if ( !$user ) {
        $Cpanel::CPERROR{'htaccess'} = locale()->maketext('The system cannot delete a user without a username.');
        print STDERR $Cpanel::CPERROR{'htaccess'} . "\n";
        return 0;
    }

    my $rDIRCFG = _htaccess_dir_setup($dir);
    $dir = $rDIRCFG->{'dir'};
    my $html_safe_dir = $rDIRCFG->{'html_safe_dir'};
    my $uri_safe_dir  = $rDIRCFG->{'uri_safe_dir'};
    my $tdir          = $rDIRCFG->{'tdir'};

    my ($file) = "$Cpanel::homedir/.htpasswds/$tdir/passwd";

    my $htlock = Cpanel::SafeFile::safeopen( \*TDP, "<", "${file}" );
    if ( !$htlock ) {
        print "Could not read from " . Cpanel::Encoder::Tiny::safe_html_encode_str($file) . "\n";
        return;
    }
    my $whtlock = Cpanel::SafeFile::safeopen( \*TDPO, ">", "${file}.tmp" );
    if ( !$whtlock ) {
        print "Could not write to " . Cpanel::Encoder::Tiny::safe_html_encode_str("$file\.tmp") . "\n";
        return;
    }
    my $skrest = 0;
    while (<TDP>) {
        if ( !$skrest ) {
            chomp();
            my ( $tuser, $tpass ) = split( /:/, $_ );
            if ( $tuser eq $user ) {
                $skrest = 1;
                next;
            }
            print TDPO;
            print TDPO "\n";
        }
        else {
            print TDPO;

        }
    }
    Cpanel::SafeFile::safeclose( \*TDPO, $whtlock );
    Cpanel::SafeFile::safeclose( \*TDP,  $htlock );

    unlink $file;
    rename "$file.tmp", $file;
    return;
}

sub getindex {
    my ( $dir, $ival ) = @_;
    return if !main::hasfeature('indexmanager');
    my $indexstatus = indextype($dir);
    if ( $indexstatus eq $ival ) { print 'checked="checked"'; }
    return;
}

=head2 setindex(DIR, VALUE, OPTS)

Adjusts the .htaccess file to change the way the web-server handles directories
that do not have index.htm, index.html, index.php or similar index files. This
function can operate in two modes:

 * Api 1 mode which preserves a lot of legacy behavior.
 * Uapi mode with adjusts the semantics to modern standards.

See below for the effects of these two modes.

MODE           | Api 1  | Uapi
----------------------------------------
Check Demo     |  yes   | no
Check Feature  |  yes   | no
Throws Errors  |  no    | yes
Print Errors   |  yes   | no
Print Output   |  yes   | no

=head3 ARGUMENTS

=over

=item DIR - string

The directory to adjust the settings for.

=item VALUE - integer

A flag indicating the way missing index files are handled for the
specific folder. It may be one of: -1 (inherits), 0 (disabled),
1 (standard index shown), 2 (fancy index shown)

=item OPTS

=over

=item uapi - boolean

When true, the call is run in UAPI mode. When false or missing the call runs in API 1 mode.

=back

=back

=head3 RETURNS

n/a

=head3 THROWS

Only when UAPI mode is selected.

=over

=item When a parameter is missing.

=item When the .htaccess file cannot be read from.

=item When the .htaccess file cannot be written.

=item When the .htaccess web-server test run fails.

=back

=cut

sub setindex {    ## no critic(Subroutines::ProhibitExcessComplexity)
    my ( $dir, $ival, %opts ) = @_;

    return if !main::hasfeature('indexmanager');

    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        print "This feature is disabled in demo mode.";
        return;
    }

    if ( !defined $dir || $dir eq '' ) {
        die Cpanel::Exception::create(
            'MissingParameter',
            [ name => 'dir' ]
        ) if $opts{uapi};
        return;
    }

    $dir = Cpanel::SafeDir::safedir($dir);
    $dir =~ s{/+}{/}g;
    $dir =~ s/\/$//g;

    my $full_dir = _safedir($dir);
    if ( !defined $full_dir ) {
        die Cpanel::Exception->create( "The system failed to setup the directory index for the “[_1]” directory: “[_2]”.", [ $dir, $! ] ) if $opts{uapi};
        return;
    }

    my $path = "$full_dir/.htaccess";

    # If there's already a .htaccess here, get its settings.
    my $hasopt      = 0;
    my $hasindexopt = 0;
    my @HC;
    if ( -e $path ) {
        eval {
            my $file = Cpanel::HttpUtils::Htaccess::open_htaccess_ro($full_dir);
            @HC = split "\n", ${ $file->get_data };
            foreach my $line (@HC) {
                if ( $line =~ /^[\s\t]*Options[\s\t]/i ) {
                    $hasopt = 1;
                }
                if ( $line =~ /^[\s\t]*IndexOptions[\s\t]/i ) {
                    $hasindexopt = 1;
                }
            }
        };
        if ($@) {
            if   ( $opts{uapi} ) { die $@ }                                         #Rethrow
            else                 { print "Failed to open existing file: $@\n"; }    # Pretty sure the previous version would continue here.
        }
    }

    if ( !$hasopt )      { push( @HC, "Options +Indexes\n" ); }
    if ( !$hasindexopt ) { push( @HC, "IndexOptions +FancyIndexing\n" ); }

    my @out_lines;    # This is here in order to avoid rewriting the following logic too much.
    foreach my $line (@HC) {
        if ( $line =~ /^[\s\t]*Options[\s\t]*(.*)/i ) {
            my (@realoptions);
            my @options = split( /[\s\t]+/, $1 );
            foreach (@options) {
                s/\n//g;
                if ( !/indexes/i && $_ ne "" ) {
                    push( @realoptions, $_ );
                }
            }
            if ( $ival == 0 ) { push( @realoptions, "-Indexes" ); }
            if ( $ival == 1 ) { push( @realoptions, "+Indexes" ); }
            if ( $ival == 2 ) { push( @realoptions, "+Indexes" ); }
            if ( $#realoptions != -1 ) {
                my $opt = join( " ", @realoptions );
                push @out_lines, "Options $opt\n";
            }
        }
        elsif ( $line =~ /^[\s\t]*IndexOptions[\s\t]*(.*)/i ) {
            my @realoptions;
            my @options = split( /[\s\t]+/, $1 );
            foreach (@options) {
                s/\n//g;
                if ( !/fancyindexing|htmltable/i && $_ ) {
                    push( @realoptions, $_ );
                }
            }
            if ( $ival == 1 ) { push( @realoptions, "-HTMLTable -FancyIndexing" ); }
            if ( $ival == 2 ) { push( @realoptions, "+HTMLTable +FancyIndexing" ); }
            if ( $#realoptions != -1 ) {
                my $opt = join( ' ', @realoptions );
                push @out_lines, "IndexOptions $opt\n";
            }
        }
        else {
            #Anything unidentified should be passed as-is, but with carriage returns enforced.
            chomp($line);
            if ( $line ne "" ) { push @out_lines, "$line\n"; }    #cut out blank lines too while we're here
        }
    }

    eval {
        my $transaction = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($full_dir);
        $transaction->set_data( \join "", @out_lines );
        my ( $status, $msg ) = Cpanel::HttpUtils::Htaccess::test_and_install_htaccess(
            'installdir'     => $full_dir,
            'htaccess_trans' => $transaction,
        );
        if ( not $status ) { die $msg }
    };
    if ($@) {
        if ( $opts{uapi} ) {
            die Cpanel::Exception->create( "The system failed to update the directory index settings for “[_1]” file: “[_2]”.", [ $path, $@ ] );
        }
        else {
            print "unavailable. Failed to alter index settings.\n" . Cpanel::Encoder::Tiny::safe_html_encode_str($path) . ": $@";
            return;
        }
    }
    elsif ( !$opts{uapi} ) {

        # print the output for API1
        if ( $ival == -1 ) { print "set to the System Default\n"; }
        if ( $ival == 0 )  { print "Off\n"; }
        if ( $ival == 1 )  { print "On\n"; }
        if ( $ival == 2 )  { print "On (fancy)\n"; }
    }

    return;
}

=head2 indextype(DIR, OPTS)

Implements the lookup of what happens when a web directory does not include a
index.htm, index.html, index.php or similar file. This is used for both the API1
implementation and the UAPI implementation.  If you don't pass any options, it
uses API 1 semantics. If you pass the options C<uapi => 1>, then the function
uses UAPI semantics.

 * Api 1 mode which preserves a lot of legacy behavior.
 * Uapi mode with adjusts the semantics to modern standards.

See below for the effects of these two modes.

MODE           | Api 1  | Uapi
----------------------------------------
Check Demo     |  yes   | no
Check Feature  |  yes   | no
Throws Errors  |  no    | yes
Print Errors   |  yes   | no
Print Output   |  yes   | no


=head3 ARGUMENTS

=over

=item DIR - string

The directory you want to lookup the indexing rules for.

=item OPTS - hash

=over

=item uapi - use uapi semantics. Defaults to false.

=back

=back

=head3 RETURNS

number - the mode for the index

=head3 THROWS

Only in uapi mode:

=over

=item When the .htaccess file in the current directory can not be opened.

=item When the .htaccess file handle can not be closed. (This usually indicates a read problem)

=back

=cut

sub indextype {
    my ( $dir, %opts ) = @_;
    return -1 if !$opts{uapi} && !main::hasfeature('indexmanager');

    my $full_dir = _safedir($dir);

    my $hasindex = -1;    # inherits
    my $htc_fh;

    my $path = $full_dir . '/.htaccess';
    if ( !open( $htc_fh, '<', $path ) ) {
        if ( $opts{uapi} ) {
            if ( $! == ENOENT ) {
                die Cpanel::Exception::create( 'DirectoryDoesNotExist', [ dir => $full_dir ] ) if !-d $full_dir;
                return -1;    # it inherits from its parent folder
            }
            else {
                die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $path, error => $! ] );
            }
        }
        else {
            return 0;
        }
    }

    while ( readline($htc_fh) ) {
        if ( /^[\s\t]*options/i && /[\s\t]*(\-?)indexes/i ) {
            if ( $1 eq '-' ) {
                $hasindex = 0;    #no indexes
                last;
            }
            else {
                if ( $hasindex != 1 ) {
                    $hasindex = 2;    #fancy
                }
            }
        }
        if ( /^[\s\t]*IndexOptions/i && /[\s\t]*(\-?)FancyIndexing/i ) {
            if ( $1 eq '-' ) {
                $hasindex = 1;        #not fancy
            }
        }
    }

    close($htc_fh) or do {
        if ( $opts{uapi} ) {
            die Cpanel::Exception::create( 'IO::FileCloseError', [ path => $path, error => $! ] );
        }
    };
    return $hasindex;
}

sub hasleech {
    my $dir = shift;

    $dir = Cpanel::SafeDir::safedir($dir);
    $dir =~ s/\/$//g;

    my $htaccess = $dir . '/.htaccess';
    my $htc_fh;
    if ( !open( $htc_fh, '<', $htaccess ) ) {
        return 0;
    }

    while ( readline($htc_fh) ) {
        if (/LeechProtect/) {
            close($htc_fh);
            return 1;
        }
    }
    close($htc_fh);
    return 0;
}

=head2 has_leech_protection($dir)

Gets the leech protection status for a given directory.

=head3 ARGUMENTS

=over 1

=item $dir - string

The path of the directory. This can be the absolute path
or the path relative to a users home directory.

=back

=head3 RETURNS

integer - the status as an integer where 0 is off and 1 is on.

=cut

sub has_leech_protection {
    my $dir = shift;
    $dir = _safe_dir($dir);

    my $htaccess = $dir . '/.htaccess';
    my $htc_fh;
    eval { Cpanel::Autodie::open( $htc_fh, '<', $htaccess ) };
    if ( my $exception = $@ ) {
        if ( $exception->error_name() eq 'ENOENT' ) {
            return 0;
        }
        else {
            die $exception;
        }
    }

    my $status = 0;
    while ( my $line = readline($htc_fh) ) {
        chomp $line;
        if ( $line =~ m/RewriteCond\s+\$\{LeechProtect:/ ) {
            $status = 1;
            last;
        }
    }

    Cpanel::Autodie::close($htc_fh);

    return $status;
}

my $webserver_role_webprotect_feature = {
    func          => 'api2_listusers',
    needs_role    => 'WebServer',
    needs_feature => 'webprotect',
    allow_demo    => 1,
};

our %API = (
    listusers => $webserver_role_webprotect_feature,
    listuser  => $webserver_role_webprotect_feature,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub _safedir {
    my $dir = shift;
    return if !$dir;

    $dir = Cpanel::SafeDir::safedir($dir);
    $dir =~ s{/+}{/}g;
    $dir =~ s/\/$//g;
    return $dir;
}

sub _htaccess_dir_setup {
    my $dir = shift;
    return if !$dir;

    $dir = _safedir($dir);

    return if !-x $dir;

    my $tdir = _virtual_dir($dir);

    my %CFG = (
        'html_safe_dir' => Cpanel::Encoder::Tiny::safe_html_encode_str($dir),
        'uri_safe_dir'  => Cpanel::Encoder::URI::uri_encode_str($dir),
        'dir'           => $dir,
        'tdir'          => $tdir,
    );
    return \%CFG;
}

1;
