package Cpanel::Config::userdata::Guard;

# cpanel - Cpanel/Config/userdata/Guard.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Config::userdata::Guard - write access to userdata (vhost config)

=head1 SYNOPSIS

    #open/create main userdata
    $udguard = Cpanel::Config::userdata::Guard->new($username);

    #create new non-SSL vhost’s userdata
    $udguard = Cpanel::Config::userdata::Guard->new(
        $username,
        $vhost_name,
        { main_data => $main_udguard_data },
    );

    #create a new SSL vhost’s userdata - same invocation as previous
    $udguard = Cpanel::Config::userdata::Guard->new_ssl( ... )

    #open a non-SSL vhost’s userdata
    $udguard = Cpanel::Config::userdata::Guard->new(
        $username,
        $vhost_name,
    );

    #open an SSL vhost’s userdata - same invocation as previous
    $udguard = Cpanel::Config::userdata::Guard->new_ssl( ... )

    #Make all changes to this hash reference.
    my $data_hr = $udguard->data();

    $udguard->save() or die "Save failed; check the log.";
    $udguard->abort();

=head1 METHODS

=cut

use strict;
use warnings;

use Cpanel::Debug                       ();
use Cpanel::CachedDataStore             ();
use Cpanel::PwCache                     ();
use Cpanel::Config::userdata::Utils     ();
use Cpanel::Exception                   ();
use Cpanel::SafeDir::MK                 ();
use Cpanel::Config::userdata::Constants ();
use Cpanel::Destruct                    ();

=head2 I<CLASS>->new_ssl( USER, VHOST_NAME, OPTS_HR )

Open or create an SSL vhost’s userdata. C<OPTS_HR> is only
used for creation (and is required for that case).

See C<new()> below for further details.

=cut

sub new_ssl {
    my ( $class, $user, $domain, $opts_hr ) = @_;

    die 'This method is only for SSL domains.' if !$domain;

    return new( $class, $user, "${domain}_SSL", $opts_hr );
}

=head2 I<CLASS>->new( ... )

Open or create a userdata file.

There are three variants of the call syntax for three different
uses:

=over

=item I<CLASS>->new( USER )

Create or open a user’s main userdata. This must be done before
creating or opening any other userdata for the user.

=item I<CLASS>->new( USER, VHOST_NAME )

Open a user’s pre-existing (non-SSL) userdata. (For SSL, use the
C<new_ssl()> method.) The userdata file MUST already exist when
this syntax is used, and the VHOST_NAME must exist in the user’s main
userdata file as either the main domain or a subdomain.

=item I<CLASS>->new( USER, VHOST_NAME, { main_data => MAIN_DATA_HR, skip_checking_main_for_new_domain => 0 } )

Create a new (non-SSL) userdata file. (For SSL, use the
C<new_ssl()> method.) MAIN_DATA_HR is the value of this class’s C<data()>
method on an object that opens the user’s B<main> userdata file.

The userdata file MUST NOT already exist
when this syntax is used, and the VHOST_NAME must exist in
MAIN_DATA_HR as either the main domain or a subdomain.

If the 'skip_checking_main_for_new_domain' flag is passed the system skips the
check to see if the domain being created is in the main
userdata.  This flag should only be used if a lock
on the main userdata is obtained right before
obtaining a lock on the userdata for
the domain that is being created in the system.

=back

For example, creating a new account would look like:

    my $udmain = Cpanel::Config::userdata::Guard->new( $username );
    $udmain->data()->{'main_domain'} = $domain;

    my $ud_domain = Cpanel::Config::userdata::Guard->new(
        $username,
        $domain,
        { main_data => $udmain->data() },
    );

    #... make changes to $ud_domain->data() ...

    #Note this save order!!
    $ud_domain->save();
    $udmain->save();

=cut

#NB: We call the variable $file rather than $vhost because it can,
#in fact, be "${vhost}_SSL" if the new_ssl() wrapper was called.
#That’s meant more as an implementation detail, though, so it’s
#not documented.
sub new {
    my ( $class, $user, $file, $opts_hr ) = @_;

    # We could be more explicit about the NUL byte error message here
    # … but to what gain?
    die "Invalid user: [$user]"          if !$user || $user =~ tr<\0/><>;
    die "Invalid userdata file: [$file]" if $file && $file  =~ tr<\0/><>;

    $file = 'main' unless length $file;

    my $path = "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/$file";
    my $self = bless {
        user => $user,
        file => $path
    }, $class;
    if ( -f $path ) {
        if ( $opts_hr->{'main_data'} ) {
            die Cpanel::Exception->create_raw("“$user” already has a userdata file “$file”, but “$class” is instantiated with the syntax to create a new file.");
        }

    }
    elsif ( !-d $Cpanel::Config::userdata::Constants::USERDATA_DIR ) {
        if ( $file ne 'main' ) {
            die "“$user” has no userdata directory!";
        }
    }

    #Before we create a new userdata file, let’s make sure $domain
    #is actually supposed to have one.
    elsif ( $file ne 'main' && !$opts_hr->{'skip_checking_main_for_new_domain'} ) {
        my $main_ud = $opts_hr->{'main_data'} or do {
            my $msg = "“$user” has no userdata for “$file”; pass in “main_data”.";
            Cpanel::Debug::log_warn($msg);
            die Cpanel::Exception->create_raw($msg);
        };

        #strip trailing “_SSL” without using pattern-match engine
        my ($domain) = ( split m<_SSL\z>, $file )[0];

        #suppress useless “undef” warnings
        $main_ud->{'main_domain'} ||= q<>;

        my $match = grep { $_ eq $domain } (
            $main_ud->{'main_domain'},
            @{ $main_ud->{'sub_domains'} },
        );

        if ( !$match ) {
            die Cpanel::Exception->create_raw("$domain is neither $user’s main domain ($main_ud->{'main_domain'}) nor one of that user’s subdomains (@{ $main_ud->{'sub_domains'} })!");
        }
    }
    elsif ( $file eq 'main' ) {

        # If we are creating the 'main' userdata for the first
        # time the directory will not exist so it must be
        # created here.
        $self->_ensure_userdata_dir();
    }

    my $datastore = Cpanel::CachedDataStore::loaddatastore( $path, 1 );    # lock and load
    if ( !$datastore->{'safefile_lock'} ) {
        die "The system failed to lock the userdata at “$path”.";
    }

    $datastore->{'data'} ||= {};                                           # Make certain we have a data object
    Cpanel::Config::userdata::Utils::sanitize_main_userdata( $datastore->{'data'} ) if $file eq 'main';

    @{$self}{qw(datastore locked)} = ( $datastore, 1 );
    return $self;
}

=head2 $data_hr = I<OBJ>->data()

Returns a hash reference to the datastore’s data.

=cut

sub data { return ( shift->{'datastore'}->{'data'} ||= {} ); }

=head2 $path = I<OBJ>->path()

Returns the path of the file.

=cut

sub path { return $_[0]->{'file'}; }

=head2 $ok = I<OBJ>->save()

Save the data and release the lock. Be sure to check the return value
for whether or not the save succeeded; specifics of errors are sent to the
cPanel error log.

=cut

sub save {
    my ($self) = @_;

    if ($>) {
        Cpanel::Debug::log_warn("Cannot save() while unprivileged!");
        return;
    }

    if ( !$self->{'datastore'}{'safefile_lock'} ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("Attempted to save without a lock");
    }

    $self->_ensure_userdata_dir();

    local $@;
    my $status = eval { Cpanel::CachedDataStore::savedatastore( $self->{'file'}, $self->{'datastore'} ); };
    warn if $@;

    $self->{'locked'} = 0 if $status;
    return $status;
}

=head2 I<OBJ>->abort()

Release the datastore lock B<without> saving. Any changes you’ve made to
the C<data()> will not be saved.

=cut

sub abort {
    my ($self) = @_;
    Cpanel::CachedDataStore::unlockdatastore( $self->{'datastore'} );
    $self->{'locked'} = 0;
    return;
}

sub _ensure_userdata_dir {
    my ($self)       = @_;
    my $user         = $self->{'user'};
    my $userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;

    my $user_userdata_dir = "$userdata_dir/$user";
    if ( !-e $user_userdata_dir ) {
        if ( !-e $userdata_dir ) {
            if ( !Cpanel::SafeDir::MK::safemkdir( $userdata_dir, '0711' ) ) {
                Cpanel::Debug::log_warn("Failed to create cpanel userdata directory ($userdata_dir): $!");
                return;
            }
        }
        if ( !Cpanel::SafeDir::MK::safemkdir( $user_userdata_dir, '0750' ) ) {
            Cpanel::Debug::log_warn("Failed to create user directory ($userdata_dir/$user) in cpanel userdata: $!");
            return;
        }
        my ( $cur_uid, $cur_gid ) = ( stat $user_userdata_dir )[ 4, 5 ];
        my $user_gid = ( Cpanel::PwCache::getpwnam_noshadow($user) )[3];
        if ( $cur_uid != 0 || $cur_gid != $user_gid ) {
            if ( !chown( 0, $user_gid, $user_userdata_dir ) ) {
                Cpanel::Debug::log_warn("Failed to set ownership on user directory ($userdata_dir/$user) in cpanel userdata: $!");
                return;
            }
        }
    }
    return;
}

#----------------------------------------------------------------------

sub DESTROY {
    my ($self) = @_;

    return unless $self->{'locked'};
    return if Cpanel::Destruct::in_dangerous_global_destruction();
    Cpanel::CachedDataStore::unlockdatastore( $self->{'datastore'} );

    return;
}
1;
