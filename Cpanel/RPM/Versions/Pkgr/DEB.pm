package Cpanel::RPM::Versions::Pkgr::DEB;

# cpanel - Cpanel/RPM/Versions/Pkgr/DEB.pm         Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::RPM::Versions::Pkgr::DEB

=head1 DESCRIPTION

A class invoked by Cpanel::RPM::Versions::File on debian systems to allow it to interact with the local
packaging systems it install/remove packages.

=head1 SYNOPSIS

    my $pkgr = Cpanel::RPM::Versions::Pkgr->new;
    $pkgr->installed_packages
    $pkgr->uninstall_packages
    ...

=cut

use cPstrict;
use parent 'Cpanel::RPM::Versions::Pkgr';

use Cpanel::Binaries::Debian::Dpkg      ();
use Cpanel::Binaries::Debian::DpkgQuery ();
use Cpanel::Parser::DpkgQuery           ();
use Cpanel::SafeChdir                   ();

use Digest::MD5 ();
use List::Util  ();

use constant package_extension => '.deb';
use constant dpkg_info_dir     => '/var/lib/dpkg/info';

=head1 METHODS

=head2 pkgr ($self)

Provides access to the underlying packaging binary's object (Cpanel::Binaries::Debian::Dpkg). This is mostly a private method.

=cut

sub pkgr ($self) { return $self->{'dpkg'} ||= Cpanel::Binaries::Debian::Dpkg->new }    # not required, here as a security

=head2 installed_packages ($self)

Provides a cached list in the form of a hash ref of packages and their
installed versions. On Debian systems, we exclude packages which have
been removed but not purged.

=cut

sub installed_packages ($self) {
    return $self->{'installed_packages'} if $self->{'installed_packages'};

    my $installed_packages = $self->pkgr->installed_packages;
    my %installed;
    foreach my $package ( keys %$installed_packages ) {

        # Ignore packages removed but not purged
        next if ( $installed_packages->{$package}->{'user_requested'} // '' ) eq 'r' && ( $installed_packages->{$package}->{'current_state'} // '' ) eq 'c';
        $installed{$package} = $installed_packages->{$package}->{'ver_rel'};
    }
    return $self->{'installed_packages'} = \%installed;
}

=head2 test_install ( $self, $download_dir, $pkg_files, $uninstall_hash )

Ideally this will attempt to determine if install will succeed before it tries. Unlike RPM, Debian does not
have a built in technique for checking this.

This method tries to answer a specific question: After taking into account all the
changes to the currently installed packages, are the dependencies of these new
packages satisfied by what is available?

We do this by:

=over 4

=item * We collect the list of installed packages

=item * We add all the packages that we ourselves are about to install

To this list, we also add the C<provides> list for these packages because
those are also artifacts that are part of the dependency management.

The list of these packages is one of the method arguments.

=item * We remove the packages that we know we are about to uninstall

This requires retrieving their C<provides> list as well, because those
could be referenced as a dependency.

The list of these packages is one of the method arguments.

=item * Lastly, we check the dependencies of our packages to install against
this list to see if it is satisfied

This is our second pass on the list of packages to install. The first pass
was to add all of these (and their C<provides> list) to the list that
represents what we believe the state of packages will be when we are about
to install.

Imagine we want to install C<Foo> and it requires C<Bar>. If C<Bar> is not
available, we think we will fail. However, if C<Bar> is also part of the
packages we intend to install, then it C<will> be available.

This is why we first write add C<Foo> and C<Bar> to the list as if they are
already installed, so we can make sure that C<Foo> has C<Bar> available.

=back

=cut

sub test_install ( $self, $download_dir, $pkg_files, $uninstall_hash ) {    ## no critic qw(ManyArgs) - mis-parse
    my $chdir = Cpanel::SafeChdir->new($download_dir);

    $self->acquire_lock;

    # Use apt-get binary to figure out if our dpkg command will succeed later.
    $self->logger->info("Testing Deb transaction");

    # Initial data
    my $dpkg_query_output   = Cpanel::Binaries::Debian::DpkgQuery->new->cmd('--status');
    my $installed_dpkg_data = Cpanel::Parser::DpkgQuery::parse_string( $dpkg_query_output->{'output'} // '' );

    # Remove all the packages to remove
    delete $installed_dpkg_data->@{ keys $uninstall_hash->%* };

    # Add whatever the files will add
    my %data_per_file;
    foreach my $filename ( $pkg_files->@* ) {
        my $output      = $self->pkgr->cmd( '-I', $filename );
        my $dpkg_string = ( $output->{'output'} // '' ) =~ s/^\s//xmsgr;
        my $dpkg_data   = Cpanel::Parser::DpkgQuery::parse_string($dpkg_string);

        values $dpkg_data->%* == 0
          and die "Found no packages when checking file '$filename'";

        values $dpkg_data->%* >= 2
          and die "Found multiple packages when checking one file";

        my $pkg_data = ( values $dpkg_data->%* )[0];
        $installed_dpkg_data->{ $pkg_data->{'package'} } = $pkg_data;
        $data_per_file{$filename} = $pkg_data;
    }

    # Inline the provides list to make the search faster
    foreach my $pkg_name ( keys $installed_dpkg_data->%* ) {
        $installed_dpkg_data->{$_} = {} for keys %{ $installed_dpkg_data->{$pkg_name}{'provides'} // {} };
    }

    # After we created the complete list of what the packages list
    # will look like after the uninstall and install steps,
    # we can see if our packages will have all their dependencies met
    foreach my $filename ( $pkg_files->@* ) {
        my $pkg_data = $data_per_file{$filename};
        my @packages = map { keys $pkg_data->{$_}->%* } qw< depends recommends suggests pre_depends >;

        # There are no dependencies for this package
        @packages
          or next;

        # Are any of these packages missing from our new list?
        my @unavailable = grep !$installed_dpkg_data->{$_}, @packages
          or next;

        my $error_message = sprintf "Test install failed for '%s' with missing dependencies: %s",
          $filename, join ', ', @unavailable;

        $self->logger->fatal($error_message);
        die $error_message;
    }

    $self->logger->info('Deb transaction succeeded!');
    return;
}

=head2 install ( $self, $download_dir, $preinstall, $pkg_files )

This attempts to install a list of downloaded packages located in $download_dir. If the install fails, the errors are logged. In the event, we're
not in a $preinstall, the logger will notify by email of errors when done.

=cut

sub install ( $self, $download_dir, $preinstall, $pkg_files ) {    ##no critic(Subroutines::ProhibitManyArgs)
    my $chdir = Cpanel::SafeChdir->new($download_dir);

    # So, if you have a list of packages to install,
    # and one of the packages is a dependency of one of the other in the set,
    # dpkg will happily die out when you have not yet installed a dep in the
    # list of packages you passed it due to it processing each package
    # sequentially.
    # As such if you don't find some way to ensure this doesn't happen
    # "in the wrong order", you can get failures like happen in rpm.versions
    # with the split out of the cpanel plugins to roundcube from the main
    # roundcube package before we sorted this.
    # It's a somewhat "stupid" way to fix this, as it only accidentally works
    # due to the dep being later in the sort order alphabetically,
    # but it worked and didn't cause trouble elsewhere, so we went with it.
    # It certainly is a lot easier than writing our own dep resolver just so
    # that dpkg doesn't croak needlessly.
    my @packages   = List::Util::uniq(@$pkg_files);
    my %names      = map  { my ($n) = split( '_', $_, 2 ); ( $_, $n ) } @packages;
    my @to_install = sort { $names{$a} cmp $names{$b} } @packages;

    $self->logger->info( 'Installing new packages: ' . join( ' ', @to_install ) );

    my $result = $self->run_with_logger( qw/-i --force-confold --force-confmiss/, @to_install );

    my $errors = $self->_parse_dpkg_errors($result);
    if ($errors) {
        $self->logger->error("The following possible errors were detected while installing packages:");
        $self->logger->error($errors);
        $self->logger->set_need_notify() unless $preinstall;    # Notify on completion of these errors but only on the main transaction.
    }

    return $errors;
}

=head2 uninstall ( $self, $packages ) {

Attempts to remove the packages listed in the array ref $packages from the OS.

=cut

sub uninstall ( $self, $packages ) {
    my @to_erase = sort { $a cmp $b } List::Util::uniq(@$packages);
    $self->logger->info( 'Uninstalling unneeded packages: ' . join( ' ', @to_erase ) );

    my $result = $self->run_with_logger( '--purge', '--force-all', @to_erase );

    my $errors = $self->_parse_dpkg_errors($result);

    if ($errors) {
        $self->logger->error("The following possible errors were detected while uninstalling packages:");
        $self->logger->error($errors);
        $self->logger->set_need_notify();
    }
    $self->clear_installed_packages_cache;

    return scalar @to_erase;
}

=head2 uninstall ( $self, $packages )

Attempts to remove the packages listed in the array ref $packages from the OS. It will do this despite dependency
loss as the later call to install will meet those.

=cut

sub uninstall_leave_files ( $self, @packages ) {

    my @to_erase = sort { $a cmp $b } List::Util::uniq(@packages);

    # Remove the packages.
    $self->logger->info( "Removing " . scalar @to_erase . " broken packages: " . join( ', ', @to_erase ) );

    # Ignore the output and the result. We'll still log it.
    $self->run_with_logger( qw{--remove --force-remove-reinstreq --force-depends}, @to_erase );

    $self->clear_installed_packages_cache;

    return;
}

=head2 what_owns ( $self, $file )

Attempts to determine what package owns $file.

=cut

sub what_owns ( $self, $file ) {
    return $self->pkgr->what_owns($file);
}

=head2 get_dirty_packages ( $self, $installed_array, $skip_digest_check )

Analyzes installed packages to determine if any have been changed since they were installed.

=cut

sub get_dirty_packages ( $self, $installed_array, $skip_digest_check ) {    ## no critic qw(ManyArgs) - mis-parse
    my $install_info = $self->pkgr->installed_packages;

    my %broken_packages;
    foreach my $package ( sort { $a cmp $b } keys %$install_info ) {
        next unless grep { $_ eq $package } @$installed_array;    #don't report on it if it's not installed.
        my $info = $install_info->{$package};

        # Ignore packages removed but not purged
        next if $info->{'user_requested'} eq 'r' && $info->{'current_state'} eq 'c';

        my $response = $self->_check_package_stability( $package, $skip_digest_check );
        if ($response) {
            $broken_packages{$package} = [$response];
            next;
        }

        next
          if $info->{'user_requested'} eq 'i'
          && $info->{'current_state'} eq 'i'
          && !$info->{'package_errors'};

        my $reason = sprintf( "%s%s%s", $info->{'user_requested'}, $info->{'current_state'}, $info->{'package_errors'} // '' );
        $broken_packages{$package} = [ [ 'all' => $reason ] ];
    }

    return \%broken_packages;

}

sub _check_package_stability ( $self, $package, $skip_digest_check = 0 ) {

    my %expected_md5;

    # Check that the files exist.
    open( my $mdfh, '<', dpkg_info_dir . "/$package.md5sums" )
      or return [ sprintf( "%s/%s.md5sums", dpkg_info_dir, $package ), 'All package md5 info is missing' ];

    while ( my $line = <$mdfh> ) {
        chomp $line;
        my ( $md5, $file ) = split( " ", $line, 2 );
        $file = "/$file" if index( $file, '/' ) != 0;
        $expected_md5{$file} = $md5;
        lstat($file) and next;
        return [ $file, 'File is missing' ];
    }
    close $mdfh;

    open( my $lstfh, '<', dpkg_info_dir . "/$package.list" )
      or return [ sprintf( "%s/%s.list", dpkg_info_dir, $package ), 'Package list is missing' ];

    while ( my $file = <$lstfh> ) {
        chomp $file;
        $file = "/$file" if index( $file, '/' ) != 0;
        next             if $expected_md5{$file};       # we already checked this as it's mentioned in the md5sums file.
        lstat($file) and next;
        return [ $file, 'File is missing' ];
    }
    close $lstfh;

    return if $skip_digest_check;

    my $digest = Digest::MD5->new;
    foreach my $file ( sort keys %expected_md5 ) {
        open( my $md5fh, '<', $file ) or return [ $file, 'File is not readable' ];
        $digest->addfile($md5fh);
        $digest->hexdigest eq $expected_md5{$file} or return [ $file, "The MD5 digest (" . $digest->hexdigest . ") has changed" ];
    }

    return;
}

sub _parse_dpkg_errors ( $self, $result ) {
    return if !$result->{'output'};

    my @errors;
    foreach my $line ( split( /\n/, $result->{'output'} ) ) {
        next unless $line =~ /^error:\s*([^:]+)/;

        my $error = $1;
        $error =~ s/\s+$//;    # Strip trailing space.
        push @errors, $error;
    }

    if (@errors) {
        my $errors = join ' ', @errors;
        return $errors;
    }
    else {
        return;
    }

}

1;
