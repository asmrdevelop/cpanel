
# cpanel - Cpanel/Binaries/Rpm.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Binaries::Rpm;

=head1 NAME

Cpanel::Binaries::Rpm

=head1 DESCRIPTION

Wrapper around `rpm`. In the past most methods corresponded to switch names (qa, qf, etc).

=head1 WARNING

    ***************************************************************
    * DO NOT USE this in any new code! Prefer Cpanel::Pkgr instead
    ***************************************************************

=head1 SYNOPSIS

    my $rpmservice = Cpanel::Binaries::Rpm->new( 'with_arch_suffix' => 1 );
    $rpmservice->get_version('rpm1','rpm2');
    $rpmservice->what_owns('rpm1','rpm2')
    ...

=cut

use cPstrict;

use parent 'Cpanel::Binaries::Role::Cmd';

use Cpanel::Binaries::Gpg ();
use List::Util            ();

=head1 METHODS

=head2 bin_path

Provides the binary our parent SafeRunner should use.

=cut

sub bin_path {

    return -x '/usr/bin/rpm' ? '/usr/bin/rpm' : -x '/bin/rpm' ? '/bin/rpm' : die("Unable to find the rpm binary to install packages");
}

sub locks_to_wait_for { return qw{/var/lib/rpm/.rpm.lock /var/run/yum.pid} }
sub lock_to_hold      { return 'rpmdb' }

sub needs_lock ( $self, $action, @args ) {
    return 0 if $action eq '--query';
    return 0 if $action eq '-q' && grep { $_ eq '-p' } @args;    # `rpm -q -p` acts directly on an rpm file. We don't need a lock for this.
    return 1;
}

=head2 query(@args)

A thin wrapper around rpm --query

Returns a hashref of packages as the keys
and their versions as the values.

Returns an empty hashref on failure for
backwards compat.

=cut

sub query ( $self, @filter ) {
    ref $self eq __PACKAGE__ or _croak("query() must be called as a method.");

    my $answer = $self->cmd( '--query', '--nodigest', '--nosignature', '--queryformat', $self->_get_format_string(), @filter );
    return _format_query_response($answer);
}

=head2 installed_packages(@args)

=cut

sub installed_packages ( $self, @filter ) {
    ref $self eq __PACKAGE__ or _croak("installed_packages() must be called as a method.");

    my $answer = $self->cmd( '--query', '--nodigest', '--nosignature', '--queryformat', $self->_get_format_string(), '-a', @filter );

    return {} if $answer->{status} != 0;

    return _format_query_response($answer);

}

sub _format_query_response ($answer) {
    my $out = $answer->{output};

    return { map { ( split( m{\s+}, $_ ) )[ 0, 1 ] } grep { $_ !~ /not installed/i } split( "\n", $out ) };
}

=head2 what_owns( $self, @filter )

=cut

sub what_owns ( $self, @filter ) {

    return $self->_what_owns( my $error = 1, @filter );
}

=head2 what_owns_no_errors( $self, @filter )

similar to what_owns but do not raise errors

=cut

sub what_owns_no_errors ( $self, @filter ) {

    return $self->_what_owns( my $error = 0, @filter );
}

=head2 _what_owns( $self, $raise_error, @filter )

internal helper used by what_owns and what_owns_no_errors

=cut

sub _what_owns ( $self, $raise_error, @filter ) {

    _croak("what_owns() must be called as a method.")         unless ref $self eq __PACKAGE__;
    _croak('what_owns() requires at least one search filter') unless @filter;

    my $answer = $self->cmd(
        '--query', '--nodigest', '--nosignature', '--queryformat',    #
        $self->_get_format_string(), '-f', @filter                    #
    );

    if ($raise_error) {
        if ( $answer->{'status'} && $answer->{'output'} ) {

            # see if this is a temporary error... #
            my @not_owned = ( $answer->{'output'} =~ m/^file (.+?) is not owned by any package$/gm );
            _croak( 'The system could not find any RPM owner for the following file(s): ' . join( ', ', @not_owned ) )
              if @not_owned;
        }
        if ( $answer->{status} != 0 ) {
            _croak( 'The system could not find query for the specfied file(s): ' . join( ', ', @filter ) );
        }
    }

    my @lines = split( "\n", $answer->{'output'} );
    if ( !$raise_error ) {
        @lines = grep { $_ !~ qr{(?:is not owned by any package|No such file or directory)} } @lines;
    }

    my %rpmfiles = map { m/^(\S+)\s+(.+?)$/ } @lines;

    return \%rpmfiles;
}

=head2 qR(@args)

=cut

sub qR ( $self, @filter ) {
    ref $self eq __PACKAGE__ or _croak("qR() must be called as a method.");

    _croak('qR() requires at least one search filter')
      if !@filter;

    my $answer = $self->cmd( '--query', '--nodigest', '--nosignature', '--queryformat', $self->_get_format_string(), '-R', @filter );
    if ( $answer->{'status'} && $answer->{'output'} ) {

        # see if this is a temporary error... #
        my @not_installed = ( $answer->{'output'} =~ m/^package (.+?) is not installed$/gm );
        _croak( 'The system could not find the following RPM(s): ' . join( ', ', @not_installed ) )
          if @not_installed;
        _croak( 'The system could not query the dependencies of the package(s): ' . join( ', ', @filter ) );
    }
    elsif ( $answer->{status} != 0 ) {
        return {};
    }

    my %rpmquery = map { my $line = $_; m/^(\S+?)\s+(.+?)$/ ? ( $1, $2 ) : ( $line, undef ) } split( /\n/, $answer->{'output'} );
    return \%rpmquery;
}

=head2 list_files_from_package_path( rpm_file_path )

Convenience method to list files provided by a package (output of -qlp).

Example output:

    ( '/path/to/file1', '/path/to/file2', ... );

=cut

# Would have been qlp under the old Cpanel::RPM nomenclature
sub list_files_from_package_path ( $self, $rpm_file_path ) {
    my @args = ( '--query', '--list', '--package', '--', $rpm_file_path );
    my $out  = $self->cmd_but_warn_on_fail(@args);
    return if $out->{'status'};
    return split( m<(?:\r?\n)+>, $out->{'output'} );
}

# Would have been ql under the old Cpanel::RPM nomenclature
sub list_files_from_installed_package ( $self, $rpm_name ) {
    my @args = ( '--query', '--list', $rpm_name );
    my $out  = $self->cmd_but_warn_on_fail(@args);
    return if $out->{'status'};
    return split( m<(?:\r?\n)+>, $out->{'output'} );
}

# --query --whatprovides
sub what_provides ( $self, $search ) {
    return unless $search;
    my @args = ( '--query', '--queryformat', '%{NAME}\n', '--whatprovides', $search );
    my $run  = $self->run( args => \@args );
    if ( $run->CHILD_ERROR() ) {
        if ( 0 == index( $run->stdout(), 'no package provides' ) ) {
            return;
        }

        $run->die_if_error();
    }
    my $pkg = $run->stdout();
    chomp($pkg);
    return $pkg;
}

# used by cpaddons
sub what_provides_with_details ( $self, $search ) {

    my $field_separator  = ":,:";
    my $record_separator = ":-:";

    my @fields       = ( 'name', 'version', 'release', 'arch', 'group', 'summary', 'description' );
    my $query_format = join( $field_separator, map { "\%{$_}" } @fields ) . $record_separator;

    my @args = ( '--query', '--qf', $query_format, '--whatprovides', $search );

    my $out = $self->cmd(@args);
    return if $out->{'status'};

    my $output = $out->{'output'};

    my @records;
    for my $rpm_record ( split /\Q$record_separator\E/, $output ) {
        my %record;
        ( @record{@fields} = split /\Q$field_separator\E/, $rpm_record ) == scalar @fields or next;
        chomp @record{@fields};
        push @records, \%record;
    }

    return \@records;
}

# --query --requires
sub what_requires ( $self, $pkg ) {
    my @args = ( '--query', '--requires', $pkg );
    my $out  = $self->cmd(@args);
    return () if $out->{'status'};
    my @lines = split( /\n/, $out->{output} // '' );
    my %perl_deps;
    foreach my $l (@lines) {
        next unless $l =~ m/^(\S+)(?: (.+))?/;
        my ( $dep, $rule ) = ( $1, $2 );
        $perl_deps{$dep} = $rule // '0';
    }
    return \%perl_deps;
}

=head2 add_repo_keys( key1, key2, ... )

Imports the passed in RPM signing pubkeys so that we can trust the packages
Returns 0 or 1 based on success or failure, additionally warns on failure

=cut

sub add_repo_keys ( $self, @keys2import ) {
    my @args   = ( '--import', '--', @keys2import );
    my $import = $self->cmd_but_warn_on_fail(@args);
    return 0 if $import->{'status'};
    return 1;
}

=head2 get_version( rpm1 rpm2 ... rpmN )

Convenience method to return the version of the RPM(s) provided (output of -q).

If no version is returned, the RPM is not installed.

Example output:

    {
        rpm1 => 'version1',
        rpm2 => 'version2'
    }

=cut

sub get_version ( $self, @filter ) {
    ref $self eq __PACKAGE__ or _croak("q() must be called as a method.");

    _croak('q() requires at least one search filter')
      if !@filter;

    my $answer = $self->cmd( '--query', '--nodigest', '--nosignature', '--queryformat', $self->_get_format_string(), @filter );

    my %rpmquery = map {
        my $line = $_;
        m/^(\S+?)\s+(.+?)$/ ? ( $1, $2 ) : ( $line, undef )
    } grep {
        my $line = $_;
        $line !~ m/^package (.+?) is not installed$/gm
    } split( /\n/, $answer->{'output'} );
    return \%rpmquery;
}

=head2 has_rpm(rpm_name)

Return BOOL about the presence of the requested RPM.

Useful versus all other methods, where nonexistent RPMs throw.

=cut

sub has_rpm ( $self, $search = undef ) {
    ref $self eq __PACKAGE__ or _croak("has_rpm() must be called as a method.");

    _croak('has_rpm() requires a search filter')
      if !$search;

    my $q = $self->installed_packages($search);
    return $q && $q->{$search} ? 1 : 0;
}

=head2 install_or_upgrade_from_file( path2rpm1, path2rpm2, ... )

Installs *or* upgrades the provided packages.

Logic here was previously inside Cpanel::Plugins with the following
commentary:

This subroutine does not handle downloads as install_or_upgrade_plugins
does, but simply moves the install portion over into here so as to
pave the way for debian support.

=cut

sub install_or_upgrade_from_file ( $self, @rpm_paths ) {
    $self->run_or_die(
        '--upgrade',
        '--verbose',
        '--hash',
        '--oldpackage',
        @rpm_paths,
    );
    return;
}

=head2 verify_package ( $package, $file=undef )

Verifies a package's integrity.

Logic here was previously inside Cpanel::CpAddons::Integrity.

If you pass a file as a second argument, only the one file in that package will be validated.

Returns 0 or 1 regarding whether verification succeeded.

=cut

sub verify_package ( $self, $package, $file = undef ) {
    return 0 if !length $package;

    # The file passed is not on disk.
    return 0 if length $file && !-e $file;

    my $answer = $self->cmd( '--query', '--verify', '--verbose', $package );

    my $output = $answer->{output} // '';

    return 1 if $output =~ m/^package \Q$package\E is not installed/;    # If it's not installed, we consider that unaltered.

    if ( length $file ) {

        # Just show the one file as being altered.
        $output = join "\n", grep { m{ \Q$file\E$} } split( "\n", $output );
    }

    return 0 if $output =~ m{^\.*[^. ]}m;
    return 1;
}

=head2 package_file_is_signed_by_cpanel( path2rpm )

Checks whether a package was signed by cPanel or not.

Logic here was previously inside Cpanel::CpAddons::Integrity.

Returns 0 or 1 regarding whether package was signed by us or not.

=cut

sub package_file_is_signed_by_cpanel ( $self, $file ) {

    my $answer = $self->cmd( '--query', '--queryformat', '%{SIGPGP:pgpsig}\n', '--file', $file );
    my $sig    = $answer->{output} or return 0;

    # This is from the last 16 hex digits of the key.
    # TODO: Also allow the release key here.
    my $cpanel_rpm_fingerprint = Cpanel::Binaries::Gpg::CPANEL_FINGERPRINT();
    $cpanel_rpm_fingerprint =~ s{\s}{}g;
    $cpanel_rpm_fingerprint =~ s{^.+(.{16})$}{$1};

    return $sig =~ qr/Key ID \Q$cpanel_rpm_fingerprint\E$/i;
}

sub _get_format_string ($self) {

    # Using a format string without arch emulates CentOS 5 default rpm output, with arch emulates default CentOS 6+
    return $self->{'with_arch_suffix'} ? '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n' : '%{NAME} %{VERSION}-%{RELEASE}\n';
}

=head2 get_rpm_scripts ($self, @rpms)

=cut

sub get_rpm_scripts ( $self, @rpms ) {
    scalar @rpms or return;

    my $answer = $self->cmd( '--query', '--nodigest', '--nosignature', '--scripts', @rpms );

    return unless $answer->{'status'} || length $answer->{'output'};

    if ( scalar @rpms == 1 ) {
        return if $answer->{'status'};    # error response
        return { $rpms[0] => $answer->{'output'} };
    }

    # We have more than one rpm we needed to query and at least one of them had a script. We have to query them the hard way.
    my %scripts;
    foreach my $rpm (@rpms) {
        my $answer = $self->cmd( '--query', '--nodigest', '--nosignature', '--scripts', $rpm );
        next if $answer->{'status'};      # error response
        length $answer or next;
        $scripts{$rpm} = $answer->{'output'};
    }

    return \%scripts;
}

=head2 installed_obsoletes( @pkgs )

    What rpms are installed that are obsoleted by something else?

=cut

sub installed_obsoletes ($self) {
    my $answer    = $self->cmd( '--query', '--all', '--obsoletes' );
    my @obsoletes = List::Util::uniq( sort { $a cmp $b } map { s/ [>=<].*//; $_ } split( "\n", $answer->{'output'} // '' ) );    ## no critic(ProhibitMutatingListFunctions);

    $answer = $self->cmd( '--query', @obsoletes );
    my @installed_obsoletes = sort { $a cmp $b } grep { $_ !~ m/^package .+ is not installed/ } split( "\n", $answer->{'output'} // '' );

    return \@installed_obsoletes;
}

=head2 remove_packages_nodeps( @pkgs )

    Remove @pkgs without regard for dependencies.

=cut

sub remove_packages_nodeps ( $self, @rpms ) {
    @rpms or return '';    # Nothing to do!
    my $answer = $self->cmd( '--erase', '--nodeps', @rpms );
    return $answer->{'output'} // '';
}

sub _croak {
    require Carp;
    goto \&Carp::croak;
}

1;
