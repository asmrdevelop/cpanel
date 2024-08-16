#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/sitejet.pm Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::sitejet;

use cPstrict;
use Cpanel::Exception        ();
use Cpanel::Autodie          ();
use Cpanel::Sitejet::Publish ();
use LWP::UserAgent;
use URI::Split qw(uri_split);

use parent qw( Cpanel::Admin::Base );

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::sitejet

=head1 SYNOPSIS

  use Cpanel::AdminBin::Call ();

  Cpanel::AdminBin::Call::call ( "Cpanel", "sitejet", "ADD_API_TOKEN", {} );

=head1 DESCRIPTION

This admin bin is used to log api calls as the adminbin user.

=cut

sub _actions {
    return qw(ADD_API_TOKEN DISK_QUOTA_CHECK);
}

use constant _allowed_parents => (
    __PACKAGE__->SUPER::_allowed_parents(),
);

=head1 METHODS

=head2 ADD_API_TOKEN()

Add the token key (for Sitejet) to cP user file.

=head2 RETURNS

1 on success.
0 if no user config file.

=cut

sub ADD_API_TOKEN {
    my ( $self, $api_token ) = @_;

    # Not in known UI paths; for malicious injections that bypass UI
    die "Invalid token." if $api_token !~ /^[a-z0-9]{32}\z/;

    require Cpanel::Config::CpUserGuard;
    my $conf = Cpanel::Config::CpUserGuard->new( $self->get_caller_username() );
    return 0 if !$conf;
    $conf->{'data'}->{'SITEJET_API_TOKEN'} = $api_token;

    $conf->save() or return 0;
    return 1;
}

=head1 METHODS

=over

=item * DISK_QUOTA_CHECK -- Perform disk space check before backing up sites.

    This is a simple check to ensure we calculate if the user has enough disk
    space available to take a backup of their document_root before publishing.
    Get the available space of user by performing differential on the current
    usage and assigned quota limit. Ensure the size of user's document root is
    lesser than the available space.

    ARGUMENTS
        domain (string) -- The name of the website's domain
        The optional argument and if it is empty, it will run
        check on all user owned domains.

    RETURNS:
        Reference to hash with the following keys.
        can_backup can be 1 or 0 with 1 states that there is free space.
        available_space in MB.
        required_space in MB.
        if document_root is clean or not. It does not look in to nested sub-domain's
        directory & webdisk user's director. It checks the immediate directory of doc_root
        and returns status.
            {
              'can_backup' => 1,
              'available_space' => 100,
              'required_space'  => 10,
              'is_docroot_empty' => 1
            };

    ERRORS
        All failures are fatal.

    Note:  Will not check for size of newly built website from CMS as we have
        no idea of knowing it.

    EXAMPLE
        my $result = Cpanel::AdminBin::Call::call( 'Cpanel', 'sitejet', 'DISK_QUOTA_CHECK', $domain);

=back

=cut

sub DISK_QUOTA_CHECK ( $self, $domain = '' ) {
    my $user    = $self->get_caller_username();
    my $homedir = $self->get_cpuser_homedir();
    $self->verify_that_cpuser_owns_domain($domain) if $domain;
    require Cpanel::SysQuota;
    require Cpanel::SafeRun::Errors;
    require Cpanel::DomainLookup::DocRoot;
    my ( $used_hr, $limit_hr ) = Cpanel::SysQuota::analyzerepquotadata();
    my $current_usage = $used_hr->{$user};
    my $limit_quota   = defined $limit_hr->{$user} ? $limit_hr->{$user} : 'unlimited';
    my %doc_root      = %{ Cpanel::DomainLookup::DocRoot::getdocroots($user) };
    my @domains       = $domain ? $domain : keys %doc_root;
    my $disk_quota;

    foreach my $domain (@domains) {
        my $document_root      = $doc_root{$domain};
        my $output             = Cpanel::SafeRun::Errors::saferunallerrors( 'du', '-s', $document_root );
        my $document_root_size = ( split /\s+/, $output )[0];
        my @ignore             = _ignore_dir_list( $homedir, $document_root, \%doc_root );
        my $data               = {
            'can_backup'       => 1,
            'required_space'   => 0,
            'available_space'  => 0,
            'is_docroot_empty' => _is_empty_directory( $document_root, \@ignore )
        };
        if ( $limit_quota eq 'unlimited' ) {
            $disk_quota->{$domain} = $data;
            next;
        }
        my $available_size = $limit_quota - $current_usage;
        $data->{'can_backup'}      = ( $document_root_size < $available_size ) ? 1 : 0;
        $data->{'required_space'}  = int( $document_root_size / 1024 );
        $data->{'available_space'} = int( $available_size / 1024 );

        $disk_quota->{$domain} = $data;
    }

    return $disk_quota;
}

# Note: is_empty_directory does not check the
# subdomain directories. It also ignores the following files
# .htaccess, .well-known, 400.shtml, 401.shtml, 403.shtml, 404.shtml,
# 413.shtml, 500.shtml & cp_errordocument.shtml

sub _is_empty_directory ( $document_root, $ignore_ar ) {

    opendir( my $dh, $document_root ) or die Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => $document_root, error => $! ] );
    while ( my $file = readdir($dh) ) {

        next if grep { $_ eq $file } @$ignore_ar;
        $file = "$document_root/$file";
        if ( -d $file ) {
            my $ret = _is_empty_directory( $file, $ignore_ar );
            return $ret if $ret == 0;
        }
        return 0 if -e $file && -f $file;
    }
    return 1;
}

sub _ignore_dir_list ( $homedir, $document_root, $doc_root_hr ) {

    # get the first immediate folder name after doc root
    my @sub_docroots = map { m<$document_root/([^/\n]+)>; } values %{$doc_root_hr};

    # returns non-empty on the very first file it finds
    # skip sub domain doc_root & webdiskusers
    my @webdisks              = Cpanel::WebDisk::api2_listwebdisks( home_dir => $homedir, );
    my @webdiskusers_docroots = map {
        m<^$document_root/([^/]+)>;    # this one gives $1
    } @webdisks;

    my @ignore = (
        '.',
        '..',
        '.htaccess',
        '.well-known',
        '400.shtml',
        '401.shtml',
        '403.shtml',
        '404.shtml',
        '413.shtml',
        '500.shtml',
        'cp_errordocument.shtml',
        @sub_docroots,
        @webdiskusers_docroots,
    );
    return @ignore;
}

1;
