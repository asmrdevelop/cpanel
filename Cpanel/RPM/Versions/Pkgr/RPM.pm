package Cpanel::RPM::Versions::Pkgr::RPM;

# cpanel - Cpanel/RPM/Versions/Pkgr/RPM.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::RPM::Versions::Pkgr::RPM

=head1 DESCRIPTION

A class invoked by Cpanel::RPM::Versions::File on Red Hat based systems to allow it to
interact with the local packaging systems it install/remove packages.

=head1 SYNOPSIS

    my $pkgr = Cpanel::RPM::Versions::Pkgr->new;
    $pkgr->installed_packages
    $pkgr->uninstall_packages
    ...

=cut

use cPstrict;
use parent 'Cpanel::RPM::Versions::Pkgr';

use Cpanel::Binaries            ();
use Cpanel::IOCallbackWriteLine ();
use Cpanel::Binaries::Rpm       ();
use Cpanel::SafeChdir           ();

=head1 METHODS

=head2 pkgr ($self)

Provides access to the underlying packaging binary's object (Cpanel::Binaries::Rpm). This is mostly a private method.

=cut

sub pkgr ($self) { return $self->{'rpm'} ||= Cpanel::Binaries::Rpm->new }    # not required, here as a security

use constant package_extension => '.rpm';
use constant WARN_IF_ERRORS    => 1;

=head2 installed_packages ($self)

Provides a cached list in the form of a hash ref of packages and their
installed versions. This is mostly the output from rpm -qa

=cut

sub installed_packages ($self) {
    return $self->{'installed_packages'} ||= $self->pkgr->installed_packages;
}

=head2 test_install ( $self, $download_dir, $pkg_files, $uninstall_hash )

This method uses among other things the rpm command to determine if uninstall followed by install will succeed,
leaving the system in a stable state. It understands enough about perl rpms to know about predicted conflicts
that won't be an issue. This method will die if there's an issue.

=cut

sub test_install ( $self, $download_dir, $pkg_files, $uninstall_hash ) {    ## no critic qw(ManyArgs) - mis-parse
    my $chdir = Cpanel::SafeChdir->new($download_dir);

    $self->acquire_lock;

    # Use rpm binary to figure out if our rpm -U command will succeed later.
    $self->logger->info("Testing RPM transaction");

    my $result = $self->pkgr->cmd( '-U', '--test', '--replacepkgs', '--oldpackage', @$pkg_files );

    my $child_error = $result->{'status'} >> 8;

    my @output = split( "\n", $result->{'output'} );

    # Deal with chicken / egg scenario with upgrading between major versions of perl. It's not really a conflict but because we remove rpms before we install
    # the new ones in a separate transaction, we have to suppress this side effect in the transaction check.
    my $legacy_major_perl_version = Cpanel::Binaries::PERL_LEGACY_MAJOR();
    my $removing_legacy_perl      = grep { $_ =~ m/cpanel-perl-${legacy_major_perl_version}-/ } keys %$uninstall_hash;

    if ( $removing_legacy_perl && scalar @output ) {
        my $new_major_perl_version = Cpanel::Binaries::PERL_MAJOR();

        if ( $removing_legacy_perl && $child_error ) {
            @output = grep { $_ !~ m{^\s+file \S+ from install of cpanel-perl-$new_major_perl_version\S+ conflicts with file from package cpanel-perl-$legacy_major_perl_version\S} } @output;
        }
    }

    # Deal with chicken / egg on stuff also in the uninstall_hash but where
    # the issue is with an RPM that is relied on by some other RPM already
    # set to be uninstalled.
    if (@output) {

        # Delete the first line of output if it talks about failed deps
        splice( @output, 0, 1 ) if $output[0] =~ m{error: Failed dependencies:};
        foreach my $rpm ( keys %$uninstall_hash ) {
            @output = grep { $_ !~ m{is needed by \(installed\) \Q$rpm\E\S} } @output;
        }
    }
    $child_error = 0 if ( !@output );

    $self->logger->info( join( "\n", @output ) );
    $self->logger->warning("Exit Code: $child_error") if $child_error > 0;
    if ( $child_error > 0 ) {
        my $err = "Test install failed: $result->{output}";
        $self->logger->fatal($err);
        die $err;
    }

    $self->logger->info("RPM transaction succeeded!");
    return;    # We die if it goes wrong.
}

=head2 install ( $self, $download_dir, $preinstall, $pkg_files )

This attempts to install a list of downloaded packages located in $download_dir. If the install fails, the errors are logged. In the event, we're
not in a $preinstall, the logger will notify by email of errors when done.

=cut

sub install ( $self, $download_dir, $preinstall, $pkg_files ) {    ## no critic qw(ManyArgs) - mis-parse
    my $chdir = Cpanel::SafeChdir->new($download_dir);

    $self->acquire_lock;

    # TODO: This should move into Cpanel::Binaries::Rpm?
    my @args = ( '-Uv', '--replacepkgs', '--oldpackage', @$pkg_files );

    $self->logger->info( 'Installing new rpms: ' . join( ' ', sort { $a cmp $b } @$pkg_files ) );

    my $result = $self->run_with_logger_no_timeout(@args);

    return $self->_parse_rpm_errors( $result->{'output'}, $preinstall );
}

=head2 uninstall ( $self, $packages ) {

Attempts to remove the packages listed in the array ref $packages from the OS.

=cut

sub uninstall ( $self, $packages ) {
    $self->acquire_lock;

    $self->logger->info( 'Uninstalling unneeded rpms: ' . join( ' ', @$packages ) );

    my @to_erase = $self->_rpm_q_dedup(@$packages);

    my $result = $self->run_with_logger_no_timeout( '-e', '--nodeps', @to_erase );

    $self->_parse_rpm_errors( $result->{'output'} );

    $self->clear_installed_packages_cache;

    return scalar @to_erase;
}

=head2 uninstall ( $self, $packages )

Attempts to remove the packages listed in the array ref $packages from the OS. It will do this despite dependency
loss as the later call to install will meet those.

=cut

sub uninstall_leave_files ( $self, @packages ) {
    $self->acquire_lock;

    my @rpms_to_remove = $self->_rpm_q_dedup(@packages);

    # Remove the rpms.
    $self->logger->info( "Removing " . scalar @rpms_to_remove . " broken rpms: " . join( ', ', @rpms_to_remove ) );

    $self->run_with_logger_no_timeout( qw{-e --nodeps --justdb}, @rpms_to_remove );
    $self->clear_installed_packages_cache;

    return;
}

=head2 what_owns ( $self, $file )

Attempts to determine what package owns $file. (rpm -qf)

=cut

sub what_owns ( $self, $file ) {
    my $files = $self->pkgr->what_owns_no_errors($file);    # lol

    return $files->{$file};
}

=over

=item B<get_dirty_packages>

Returns the format from C<_fetch_altered_rpms()>.

This is a two part process. 1. Run rpm -vV and find all files considered to be
altered (see _fetch_altered_files()) 2. Run rpm -qf on files to find their
rpm package name (see _fetch_altered_rpms())

rpm -Vv output:
 S file Size differs
 M Mode differs (includes permissions and file type)
 5 MD5 sum differs
 D Device major/minor number mismatch
 L readLink(2) path mismatch
 U User ownership differs
 G Group ownership differs
 T mTime differs

=back

=cut

sub get_dirty_packages ( $self, $installed_array, $skip_digest_check ) {    ## no critic qw(ManyArgs) - mis-parse
    my $broken_files = $self->_fetch_altered_files( $installed_array, $skip_digest_check );
    return {} if ( !@$broken_files );

    return $self->_fetch_altered_rpms( $installed_array, $broken_files );

}

# ------------------------------------------------------------------------------------------------------------------------------------
#
#  Private methods go below this line.
#
# ------------------------------------------------------------------------------------------------------------------------------------

=over

=item B<_fetch_altered_files>

1. Get all rpms installed

2. Run a rpm -vv on each rpm installed and collect any non document/config
files that are considered altered

3. Return array reference with collected rpms from previous step:
each array member is a two-member array reference: [ $path => $reason ].

=back

=cut

sub _fetch_altered_files ( $self, $installed_array, $skip_digest_check = 0 ) {    ## no critic qw(ManyArgs) - mis-parse

    $self->logger->info("Looking for RPMs with modified files other than timestamp or permissions changes");
    my @broken_files;

    my @rpm_options = ( $ENV{'CPANEL_RPM_NO_DIGEST'} || $skip_digest_check ) ? qw{ --nosignature --nodigest --nomd5} : ();
    push @rpm_options, '--noscripts', '--nodeps';

    my $run = $self->pkgr->run( 'args' => [ '-V', @rpm_options, @$installed_array ] );

    my %lock;
    foreach my $line ( split( m{\n}, ${ $run->stdout_r() } ) ) {
        if ( $line =~ m{^\.M\.\.\.\.\.[T.]\.\s+/} ) {    # Warn if permissions changed only on non-doc/config files.
            $self->logger->warning("Permissions mis-match (ignored): $line");
        }
        next if ( $line =~ m/^\.[.M]\.\.\.\.\.[T.]/ );    # Skip clean rpms and ignore mtime or time changes to the files.
        next if ( $line =~ m/^\S{8,9}\s+[cdg]\s/ );       # Skip config or doc files.
        chomp $line;

        next unless ( $line =~ m/^(\S{8,9}|missing\s+[cdg]|missing)\s+(\S.*)$/ );    # Doesn't look like an rpm -V row?
        my ( $reason, $file ) = ( $1, $2 );

        # rpm verify is 9 characters, a possible attribute marker
        # we need to handle the attribute marker as well
        #.....U...  g /usr/local/cpanel/3rdparty/mailman/Mailman/Cgi/listinfo.pyc
        if ( substr( $file, 0, 1 ) =~ tr{a-z}{} && substr( $file, 1, 1 ) eq ' ' ) {
            $reason .= " " . substr( $file, 0, 2, '' );
        }
        next if $lock{$file};
        $lock{$file} = 1;
        push @broken_files, [ $file, $reason ];
    }

    $self->logger->warn( $run->stderr() ) if $run->stderr();

    # Can't check CHILD_ERROR here because error 13 can be normal

    return \@broken_files;
}

=over

=item B<_fetch_altered_rpms>

Accepts array ref of altered files. Returns a hash ref of rpms with altered files that looks like:

    {
        'cpanel-some_rpm_name53,5.3.10,5.cp1136'       => [
            ['/path/to/altered/file1','S......T.'],
            ['/path/to/altered/file2','S......T.'],
        ],
        'cpanel-some_other_rpm_name123,1.2.3,1.cp1136' => [
            ['/path/to/file','S......T.'],
            ['/another/path/to/another/file','S......T.'],
        ],
    }

i.e.:

    {
        "$name,$version,$release" => [
            [ $path => $reason ],
            ...
        ],
        ...
    }

=back

=cut

sub _fetch_altered_rpms ( $self, $installed_array, $broken_files_array ) {    ## no critic qw(ManyArgs) - mis-parse

    # Determine what packages these files are in and put it in a hash to group them.
    my %all_broken_files = map { $_->[0] => $_->[1] } @$broken_files_array;
    if ( scalar keys %all_broken_files ) {
        return $self->_get_rpm_list_for_files( \%all_broken_files, $installed_array );
    }
    return {};
}

sub _get_rpm_list_for_files ( $self, $all_broken_files_with_reasons_hr, $cpanel_rpm_list ) {    ## no critic qw(ProhibitManyArgs) - needs refactor

    # We list all files and walk though the file list and mark each
    # rpm that has a missing file to generate the rpm list.  This is a bit slower
    # then checking a few at a time so we only do this if we are missing lots of files

    my %seen_pkg;
    my $current_pkg;
    $self->pkgr->run(
        'stdout' => Cpanel::IOCallbackWriteLine->new(
            sub {
                chomp $_[0];
                if ( rindex( $_[0], '---', 0 ) == 0 ) {
                    $current_pkg = substr( $_[0], 3 );
                }
                elsif ( exists $all_broken_files_with_reasons_hr->{ $_[0] } ) {

                    # The caller expects to have an arrayref with the file and the reason
                    push @{ $seen_pkg{$current_pkg} }, [ $_[0], $all_broken_files_with_reasons_hr->{ $_[0] } ];
                }
            }
        ),
        'args' => [ '-q', '--list', '--nodigest', '--nosignature', '--queryformat', '---%{NAME},%{VERSION},%{RELEASE}\\n', @$cpanel_rpm_list ],
    );
    return \%seen_pkg;
}

sub _rpm_q_dedup ( $self, @rpms ) {
    my %seen;

    # NOTE: If the RPM isn't actually installed, nothing will come back from saferun and it'll be undef.
    # This isn't a big deal since the caller is doing this to get a list of rpms they should uninstall
    # and if it's not installed, who cares?
    my $rpm_q = $self->pkgr->cmd( '-q', @rpms ) || {};

    my @list = grep { $_ && !$seen{$_}++ } ( $rpm_q->{'output'} // '' ) =~ m/^(\S+)$/mg;
    @list = @rpms if $? || !@list;

    @list = sort { $a cmp $b } @list;
    return @list;
}

sub _parse_failed_rpm_dependencies ( $self, $output = undef ) {
    return [] unless defined $output;

    my %rpms;
    foreach my $line ( split( /\n/, $output ) ) {
        my ( $try, $blocker ) = split qr{is needed by \(installed\)\s+}i, $line;
        next unless defined $blocker;
        my @name = split '-', $blocker;
        next unless scalar @name > 2;
        pop(@name) for 1 .. 2;
        my $rpm = join '-', @name;
        $rpms{$rpm} = 1;
    }

    return [ sort keys %rpms ];
}

sub _parse_rpm_errors ( $self, $output, $preinstall = 0 ) {
    return if !$output;

    my @errors;
    foreach my $line ( split( /\n/, $output ) ) {
        if ( $line =~ /^error:\s*([^:]+)\s*/ ) {
            push @errors, $1 if $1;
        }
    }

    return unless @errors;

    my $errors = join ' ', @errors;

    $self->logger->error("The following possible errors were detected while installing RPMs:");
    $self->logger->error($errors);
    $self->logger->set_need_notify() unless $preinstall;    # Notify on completion of these errors but only on the main transaction.

    if ( -e q{/var/cpanel/dev_sandbox} ) {
        my $rpms_to_remove = $self->_parse_failed_rpm_dependencies($output);
        $self->logger->error( "Try to run:\n> rpm -e --nodeps " . join( ' ', @$rpms_to_remove ) ) if $rpms_to_remove && scalar @$rpms_to_remove;
    }

    return;
}

1;
