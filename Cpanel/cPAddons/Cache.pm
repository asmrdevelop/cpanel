
# cpanel - Cpanel/cPAddons/Cache.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Cache;

use strict;
use warnings;

use Cpanel::FileUtils::TouchFile ();
use Cpanel::LoadModule           ();

use Cpanel::Imports;

# TODO: Consider renaming to Registry

# If the optional $user parameter is undefined, read the cache as whatever user
# we're running as, but don't rewrite it unless we're root.  This should only be
# used for files we're certain are under root's control.

=head1 NAME

Cpanel::cPAddons::Cache

=head1 DESCRIPTION

Function for manipulating the cPAddons YAML files, including those under
user home directories and under /var/cpanel.

=head1 FUNCTIONS

=head2 read_cache(FILE, DATA)

Loads a YAML file for the current user.

=head2 read_cache(FILE, DATA, USER)

Loads a YAML file for a specific user.

=head3 Arguments

- FILE - String - Path to the YAML file to load

- DATA - Hash ref or array ref - A hash ref or array ref into which to load the YAML file's data structure

- USER - String - (Optional) If specified, drop privileges to this user before performing the
operation. B<Important>: If running as root and loading from a user's home directory, this must
be done to prevent symlink attacks.

=cut

sub read_cache {
    my ( $file, $data, $user ) = @_;

    $file =~ s{\.yaml$}{}g;

    return if $file =~ /\.\./;

    my $load_coderef = sub {
        require Cpanel::DataStore;
        return Cpanel::DataStore::load_ref("$file.yaml");
    };

    my $ref;

    # If we are running as root, and $user is specified as something different, we need to setuid.

    if ( ( $> == 0 || $< == 0 ) && ($user) && ( $user ne 'root' ) ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds');
        $ref = Cpanel::AccessIds::do_as_user( $user, $load_coderef );
    }
    else {
        $ref = $load_coderef->();
    }

    if ( ref($ref) eq 'HASH' ) {
        %{$data} = %{$ref};
    }
    elsif ( ref($ref) eq 'ARRAY' ) {
        @{$data} = @{$ref};
    }

    return $ref;
}

=head2 write_cache(FILE, DATA)

Writes a YAML file for the current user.

=head2 write_cache(FILE, DATA, USER)

Writes a YAML file for a specific user.

=head3 Arguments

- FILE - String - Path to the YAML file to write

- DATA - Hash ref or array ref - A hash ref or array ref containing the data structure to write to disk

- USER - String - (Optional) If specified, drop privileges to this user before performing the
operation. B<Important>: If running as root writing to a file under a user's home directory, this
must be done to prevent symlink attacks.

=cut

sub write_cache {
    my ( $file, $data, $user ) = @_;

    if ( !$file ) {
        logger()->warn("No file name provided.");
        return;
    }

    if ( ref $data ne 'HASH' ) {
        logger()->warn("Output variable not a valid hashref");
        return;
    }

    # Cleanup
    delete $data->{'password_md5'};     # binary string goofs up ASCII XML file...
    delete $data->{'license_html'};     # messes up YAML
    delete $data->{'input_license'};    # this field Storable -> YAML has odd characters that goof up Perl in between call to Load and execution of Load

    $file =~ s{\.yaml$}{}g;

    if ( $> == 0 || $< == 0 ) {
        return _write_this( "$file.yaml", $data ) if !$user || $user eq 'root';

        if ( my $pid = fork() ) {
            waitpid( $pid, 0 );
        }
        else {
            Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::SetUids');
            Cpanel::AccessIds::SetUids::setuids($user);
            _write_this( "$file.yaml", $data );
            exit();
        }
    }

    return _write_this( "$file.yaml", $data );
}

sub _write_this {
    my ( $file, $data ) = @_;
    my $old_umask = umask 077;
    Cpanel::FileUtils::TouchFile::touchfile($file) if !-e $file;
    chmod 0600, $file;
    umask $old_umask;
    require Cpanel::DataStore;
    return Cpanel::DataStore::store_ref( $file, $data );
}

1;
