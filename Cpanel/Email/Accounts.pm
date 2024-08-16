package Cpanel::Email::Accounts;

# cpanel - Cpanel/Email/Accounts.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Autodie                       ();
use Cpanel::Email::Accounts::Cache        ();
use Cpanel::Exception                     ();
use Cpanel::JSON                          ();
use Cpanel::LoadFile                      ();
use Cpanel::LoadFile::ReadFast            ();
use Cpanel::LoadModule                    ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Email::Accounts::Paths        ();
use Cpanel::PwCache                       ();
use Cpanel::Alarm                         ();

use constant _EDQUOT => 122;

our $VERSION  = 3;
our $DEBUG    = 0;
our $EMAILTTL = 60 * 60 * 4;
our $TIMEOUT  = 15;

my ( $logger, $locale );

our $EMAIL_ACCOUNTS_CACHE_FILE = 'email_accounts.json';

###########################################################################
# Method:
#   manage_email_accounts_db
#
# Description:
#   A Cache database for active email accounts belonging to a cPanel user
#
# Parameters:  A hash with the following keys:
#
#   event - An event to apply to the cache database
#    - sync            - Search the disk for shadow, maildirsize, and quota files and ensure
#                       the database is in sync with their contents
#    - fetch (default) - Returns the existing database contents if no_validate is set, otherwise it becomes 'sync'
#    - add             - Adds a new account to the database
#    - remove          - Removes an account from the database
#
#   no_validate - Returns the cache data as-is without updating it to be in sync with the shadow and quota files
#
#   no_disk - Skip updating the disk usage information in the cache (this can be very slow without this flag)
#
#   matchdomain - Only return entries in the cache for the specified domain
#
#   ttl - Use a custom time-to-live value for the cache
#
#   email - The email address to add or remove
#
#   regex - Post filter the list of email addresses with this regex
#
#   get_restrictions - Populates suspended_outgoing, hold_outgoing, and has_suspension fields for each account
#
#  THIS CAN THROW EXCEPTIONS in some cases, but in other error cases
#  it will “return in failure” as indicated below.
#
#  Returns one- or two-part:
#   - The filtered contents of the database cache
#    Example:
#     {
#          '$DOMAIN' => {
#                                'account_count' => 1997,
#                                'shadow_mtime' => 1441739884,
#                                'quota_mtime' => 1441739884,
#                                'disk_mtime' => 1441739884
#                                'accounts' => {
#                                                '$ACCOUNT' => {
#                                                                'diskused' => 0,
#                                                                'disk_mtime' => 1441739884
#                                                              },
#                         ...
#                         }
#            }
#      ...
#      }
#     OR
#   - (undef, the error)
#
#  NOTE: In the event of “return in failure”, $Cpanel::CPERROR{'email'}
#  will be overwritten to contain the error.
#
#
sub manage_email_accounts_db {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my %OPTS = @_;
    my $now  = time();
    my $ttl  = $OPTS{'ttl'} || $EMAILTTL;

    $OPTS{'event'} ||= 'fetch';

    my $user_homedir = get_homedir();

    my ( $cpusername, @users_domains );
    if ($Cpanel::user) {
        $cpusername    = $Cpanel::user;
        @users_domains = @Cpanel::DOMAINS;
    }
    else {
        Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadCpUserFile');
        $cpusername = Cpanel::PwCache::getusername();
        my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($cpusername);
        @users_domains = ( $cpuser_ref->{'DOMAIN'}, $cpuser_ref->{'DOMAINS'} ? @{ $cpuser_ref->{'DOMAINS'} } : () );
    }
    my $email_accounts      = get_email_accounts_file_path($user_homedir);
    my $is_rw               = 0;
    my $passed_in_trans_obj = $OPTS{'transaction_obj'} ? 1 : 0;
    my $trans_obj           = $OPTS{'transaction_obj'};

    if ($passed_in_trans_obj) {
        $is_rw ||= ref $trans_obj eq 'Cpanel::Transaction::File::JSON' ? 1 : 0;
    }
    else {
        $is_rw ||= !Cpanel::Autodie::exists($email_accounts) ? 1 : 0;
        $is_rw ||= $OPTS{'event'} ne 'fetch'                 ? 1 : 0;
        $is_rw ||= !$OPTS{'no_validate'}                     ? 1 : 0;
    }

    my $privs;

    if ( $is_rw && ( $> == 0 ) ) {
        require Cpanel::AccessIds::ReducedPrivileges;
        $privs = Cpanel::AccessIds::ReducedPrivileges->new($cpusername);
    }

    if ( !$trans_obj ) {

        my $err;
        try {
            $trans_obj = get_transaction($is_rw);
        }
        catch {
            $err = $_;
        };

        # case CPANEL-4048: Attempt to create a fresh db file if loading the email accounts fails
        if ($err) {
            if ( try { $err->get('error') == _EDQUOT } ) {

                # Logger it but do not throw into the UI
                _logger()->warn($err);
            }
            else {
                local $@ = $err;
                warn;
            }
            unlink($email_accounts);
            try {
                $trans_obj = get_transaction($is_rw);
            }
            catch {
                $err = $_;
            };

            # case CPANEL-4050: Open in read-only mode in the event the disk quota is exceed or we cannot get
            # a transaction lock
            if ($err) {
                if ( try { $err->get('error') == _EDQUOT } ) {

                    # Logger it but do not throw into the UI
                    _logger()->warn($err);
                }
                else {
                    local $@ = $err;
                    warn;
                }

                $is_rw     = 0;
                $trans_obj = get_transaction($is_rw);
            }
        }
    }

    my $popdbref = {};

    try {
        $popdbref = $trans_obj->get_data();
    }
    catch {
        _logger()->warn($_);
    };

    my $no_validate = ( $OPTS{'no_validate'} ? 1 : 0 );

    #empty is ok if we have a __version key
    my $data_needs_resync = ref($popdbref) ne 'HASH' || ( $popdbref->{'__version'} || 0 ) != $VERSION;

    if ($data_needs_resync) {
        $popdbref    = {};
        $no_validate = 0;
    }

    delete $popdbref->{'__version'};

    my $modified = 0;

    my %WANTED_DOMAINS;
    if ( $OPTS{'matchdomain'} ) {
        %WANTED_DOMAINS = map { $_ => undef } grep { $_ eq $OPTS{'matchdomain'} } @users_domains;
    }
    else {
        %WANTED_DOMAINS = map { $_ => undef } @users_domains;

        # We have to account for domains that were deleted or are no longer relevant for one reason or another (i.e and will not be in @users_domains)
        #  If matchdomain is not on we do this before we save the db
        $modified = 1 if _delete_unwanted_domains( $popdbref, \%WANTED_DOMAINS );
    }
    if ( $OPTS{'event'} eq 'fetch' ) {

        #
        # We used to reset $popdbref and then rebuild it
        # since we already remove it from popdbref below this was a waste
        #
        if ($no_validate) {

            if ( $OPTS{'get_restrictions'} ) {
                _augment_popdb_with_suspend_data( $popdbref, $cpusername );
            }

            return $popdbref;
        }

        $OPTS{'event'} = 'sync';
    }

    if ( $OPTS{'event'} eq 'add' || ( $OPTS{'event'} eq 'sync' && !$OPTS{'no_disk'} ) ) {
        require Cpanel::Email::DiskUsage;
    }

    if ( $OPTS{'event'} eq 'add' || $OPTS{'event'} eq 'sync' ) {
        require Cpanel::UUID;
    }

    local $Cpanel::Email::DiskUsage::_CHECK_FOR_ROOT = 0 if $INC{'Cpanel/Email/DiskUsage.pm'} && $>;

    if ( $OPTS{'event'} eq 'add' ) {
        my ( $login, $domain ) = split( /\@/, $OPTS{'email'}, 2 );
        $popdbref->{$domain}->{'accounts'}->{$login} = {
            'diskquota'  => $OPTS{'quota'},
            'diskused'   => Cpanel::Email::DiskUsage::get_disk_used( $login, $domain ),
            'disk_mtime' => $now,
            'UUID'       => Cpanel::UUID::random_uuid(),
        };
        if ( exists $popdbref->{$domain} && exists $popdbref->{$domain}->{'shadow_mtime'} ) {
            $popdbref->{$domain}->{'shadow_mtime'} = $now;
            $popdbref->{$domain}->{'quota_mtime'}  = $now;
        }
        $modified = 1;
    }
    elsif ( $OPTS{'event'} eq 'remove' ) {
        my ( $login, $domain ) = split( /\@/, $OPTS{'email'}, 2 );
        delete $popdbref->{$domain}->{'accounts'}->{$login};
        if ( exists $popdbref->{$domain} && exists $popdbref->{$domain}->{'shadow_mtime'} ) {
            $popdbref->{$domain}->{'shadow_mtime'} = $now;
            $popdbref->{$domain}->{'quota_mtime'}  = $now;
        }
        $modified = 1;
    }
    elsif ( $OPTS{'event'} eq 'sync' ) {

        my ( $shadow_size, $shadow_mtime, $quota_mtime );

        # this is not an option, as any api call could reach that timeout
        #   the idea is to try updating as much accounts as possible in one single call
        #   all others accounts will be updated during a second pass
        #   which means that the cache will not expire at the same time for all accounts
        my $timeout_raised;
        my $alarm = Cpanel::Alarm->new(
            $TIMEOUT,
            sub {
                $timeout_raised = 1;
                print STDERR "manage_email_accounts_dbs: Alarm triggered, no more account will be updated\n" if $DEBUG;
            }
        );

      PDLOOP:
        foreach my $domain ( keys %WANTED_DOMAINS ) {

            my $shadow_path = "$user_homedir/etc/$domain/shadow";
            my $quota_path  = "$user_homedir/etc/$domain/quota";

            ( $shadow_size, $shadow_mtime ) = ( stat($shadow_path) )[ 7, 9 ];
            if ( !$shadow_size ) {
                delete $popdbref->{$domain};
                print STDERR "manage_email_accounts_dbs: Skipping sync for $domain (null shadow file)\n"
                  if $DEBUG;
                next;
            }

            ## case 32920: expunges blank $email accounts
            $modified = 1 if ( delete $popdbref->{$domain}{'accounts'}{''} );

            $quota_mtime = ( stat($quota_path) )[9] // 0;

            my @mtimes_to_check = ();

            my $skip_sync = Cpanel::Email::Accounts::Cache::can_skip_sync(
                $popdbref->{$domain},
                $now - $ttl + 1,
                $now - 1,
                shadow_mtime => $shadow_mtime,
                quota_mtime  => $quota_mtime,

                ( $OPTS{'no_disk'} ? () : ( disk_mtime => undef ) ),
            );

            #die "Skip sync? [$skip_sync, $shadow_mtime]";
            if ($skip_sync) {
                if ($DEBUG) {
                    print STDERR "manage_email_accounts_dbs: Skipping sync for $domain as it is cached and below the ttl.\n";
                }

                next;
            }

            print STDERR "manage_email_accounts_dbs: sync for $domain\n" if $DEBUG;

            $popdbref->{$domain}->{'shadow_mtime'} = $now;
            $modified = 1;

            my %in_shadow;
            my ( $login, $pw_hash );

            {
                my $shadow_fh;
                if ( !open( $shadow_fh, '<', $shadow_path ) ) {    # no need to lock as we rename() into place now
                    _logger()->warn("Could not open $shadow_path: $!");
                    next;
                }
                my $lines = '';
                Cpanel::LoadFile::ReadFast::read_all_fast( $shadow_fh, $lines );
                foreach ( split( m{\n}, $lines ) ) {
                    ( $login, $pw_hash ) = ( split( /:/, $_ ) )[ 0, 1 ];

                    next if ( !defined $login || $login =~ tr/\r\n\0// );
                    $in_shadow{$login} = 1;

                    if ( $OPTS{'no_disk'} ) {
                        $popdbref->{$domain}->{'accounts'}->{$login} ||= {};
                    }

                    #IF THERE IS NO ENTRY, AN INVALID ENTRY OR THE CACHE IS EXPIRED WE NEED TO RECREATE IT
                    elsif (
                        !$timeout_raised && (
                            !$popdbref->{$domain}->{'accounts'}->{$login}->{'disk_mtime'} ||                         # account level disk_mtime mtime is missing
                            ( ( $popdbref->{$domain}->{'accounts'}->{$login}->{'disk_mtime'} + $ttl ) < $now ) ||    # account level disk_mtime mtime exceeds ttl
                            $popdbref->{$domain}->{'accounts'}->{$login}->{'disk_mtime'} > $now                      # account level disk_mtime mtime is time warp safe
                        )
                    ) {
                        my $usage_info = Cpanel::Email::DiskUsage::get_email_account_disk_usage_file_info("$login\@$domain");
                        if ( $usage_info->{'mtime'} && ( !$popdbref->{$domain}->{'accounts'}->{$login}->{'disk_mtime'} || $usage_info->{'mtime'} >= $popdbref->{$domain}->{'accounts'}->{$login}->{'disk_mtime'} ) ) {
                            $popdbref->{$domain}->{'accounts'}->{$login}->{'diskused'}  = Cpanel::Email::DiskUsage::get_usage_from_file_info($usage_info);
                            $popdbref->{$domain}->{'accounts'}->{$login}->{'diskmtime'} = $now;
                        }
                    }

                    $popdbref->{$domain}{'accounts'}{$login}{'UUID'} ||= Cpanel::UUID::random_uuid();
                    $popdbref->{$domain}{'accounts'}{$login}{'suspended_login'} = ( substr( $pw_hash, 0, 1 ) eq '!' ) ? 1 : 0;
                }
            }

            if ( !$OPTS{'no_disk'} ) {
                $popdbref->{$domain}->{'disk_mtime'} = $now;
                $modified = 1;
            }

            ## case 32920: handle where in $email_accounts, but not /etc/shadow
            my @missing_from_shadow =
              grep { !exists $in_shadow{$_} } keys %{ $popdbref->{$domain}->{'accounts'} };
            if (@missing_from_shadow) {
                delete @{ $popdbref->{$domain}{'accounts'} }{@missing_from_shadow};
                $modified = 1;
            }

            ##
            ## Skip to the next domain if there are no accounts in this domain
            ##
            if (   !exists $popdbref->{$domain}->{'accounts'}
                || !ref $popdbref->{$domain}->{'accounts'}
                || !scalar keys %{ $popdbref->{$domain}->{'accounts'} } ) {
                $popdbref->{$domain}->{'account_count'} = 0;
                next;
            }

            ##
            ## If the quota file has been changed since we loaded the data in the quota database re-read it
            ##
            if (
                  !$popdbref->{$domain}->{'quota_mtime'}
                || $popdbref->{$domain}->{'quota_mtime'} < $quota_mtime

                #only reload this when missing or the mtime expires as we update this when we add an account
                || ( $popdbref->{$domain}->{'quota_mtime'} + $ttl ) < $now

                # or if we are past the ttl
            ) {
                if ( !-e $quota_path ) {

                    # Don't whine pointlessly about this in the context of
                    # roundcube gathering data on users. It causes "invalid
                    # log entry" warnings during update-roundcube-db that
                    # don't really help you at all.
                    # Same for many other scripts.
                    if ( $ENV{'CPANEL_DEBUG_LEVEL'} ) {
                        _logger()->debug("Quota file $quota_path does not exist; skipping quota update");
                    }
                    next;
                }
                print STDERR "manage_email_accounts_dbs: update quota for $domain\n" if $DEBUG;
                my $quota_fh;
                if ( !open( $quota_fh, '<', $quota_path ) ) {    # no need to lock since we rename() into place
                    _logger()->warn("Could not open $quota_path: $!");
                    next;
                }

                my ( $login, $quota );

                my $lines = '';
                Cpanel::LoadFile::ReadFast::read_all_fast( $quota_fh, $lines );

                foreach ( split( m{\n}, $lines ) ) {
                    tr/\0\///d;
                    next if m/^[\r\s\n]*$/;
                    ( $login, $quota ) = split( /:/, $_ );
                    chomp $quota;

                    next if ( !defined $login || !exists $popdbref->{$domain}->{'accounts'}->{$login} );

                    my $login_hash = $popdbref->{$domain}->{'accounts'}->{$login};
                    if ( !$login_hash->{'diskquota'} || $login_hash->{'diskquota'} != $quota ) {
                        $login_hash->{'diskquota'} = $quota;
                        $modified = 1;
                    }
                }

                $popdbref->{$domain}->{'quota_mtime'} = $now;
                $modified = 1;
            }
        }    # end $domain loop
    }    # end  $OPTS{'event'} eq 'sync'

    if ( $modified && $is_rw ) {
        print STDERR "manage_email_accounts_dbs: Writing email database to $email_accounts\n" if $DEBUG;

        foreach my $domain ( keys %WANTED_DOMAINS ) {
            $popdbref->{$domain}->{'account_count'} = scalar keys %{ $popdbref->{$domain}->{'accounts'} };
        }

        if ($is_rw) {
            local $popdbref->{'__version'} = $VERSION;
            $trans_obj->set_data($popdbref);
            my ( $ok, $err );
            if ($passed_in_trans_obj) {
                ( $ok, $err ) = $trans_obj->save();
            }
            else {
                ( $ok, $err ) = $trans_obj->save_and_close();
            }
            if ( !$ok ) {
                _logger()->warn( "The system encountered an error while saving the $email_accounts file: " . Cpanel::Exception::get_string($err) );
            }
        }

        my $total_accounts;
        my $db_complete = 1;
        foreach my $domain ( keys %{$popdbref} ) {
            if ( !exists $popdbref->{$domain}->{'account_count'} ) {
                $db_complete = 0;
                last;
            }
            $total_accounts += $popdbref->{$domain}->{'account_count'};
        }

        if ($db_complete) {
            try {
                require Cpanel::FileUtils::Write;
                Cpanel::FileUtils::Write::overwrite( "$user_homedir/.cpanel/email_accounts_count", $total_accounts );
            }
            catch {
                _logger()->warn( Cpanel::Exception::get_string($_) );
            };
        }
    }
    elsif ( !$passed_in_trans_obj && $trans_obj->can('close') ) {
        my ( $ok, $err ) = $trans_obj->close();
        if ( !$ok ) {
            _logger()->warn( "The system encountered an error while closing the $email_accounts file: " . Cpanel::Exception::get_string($err) );
        }
    }

    # In the below block we remove any items we do not want to display in the database
    # We have to account for domains that were deleted or are no longer relevant for one reason or another (i.e and will not be in @users_domains)
    #  If matchdomain is on we have to do it after we write the db to prevent removing stuff we may want later
    if ( $OPTS{'matchdomain'} ) {
        _delete_unwanted_domains( $popdbref, \%WANTED_DOMAINS );
    }
    if ( $OPTS{'regex'} ) {
        my $regex;
        eval {
            local $SIG{'__DIE__'};
            $regex = qr/$OPTS{'regex'}/i;
        };
        if ( $@ || !$regex ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
            $locale ||= Cpanel::Locale->get_handle();
            my $error = $locale->maketext( '“[_1]” is not a valid [asis,Perl] regular expression.', $OPTS{'regex'} );
            $Cpanel::CPERROR{'email'} = $error;    ## backwards compat
            return ( undef, $error );
        }
        foreach my $domain ( keys %{$popdbref} ) {
            delete @{ $popdbref->{$domain}->{'accounts'} }{ grep { ( ( $_ || '' ) . '@' . $domain ) !~ $regex } keys %{ $popdbref->{$domain}->{'accounts'} } };
        }
    }
    if ( $OPTS{'get_restrictions'} ) {
        _augment_popdb_with_suspend_data( $popdbref, $cpusername );
    }

    return $popdbref;
}

sub get_transaction {
    my ($is_rw) = @_;

    $is_rw = 1 unless defined $is_rw;    # default to RW
    my %args = ( path => get_email_accounts_file_path(), permissions => 0600 );

    if ($is_rw) {
        require Cpanel::Transaction::File::JSON;
        return Cpanel::Transaction::File::JSON->new(%args);
    }

    return Cpanel::Transaction::File::JSONReader->new(%args);
}

sub get_email_accounts_file_path {
    my ($user_homedir) = @_;
    $user_homedir ||= get_homedir();
    return "$user_homedir/.cpanel/$EMAIL_ACCOUNTS_CACHE_FILE";
}

sub get_homedir {
    return $Cpanel::homedir || Cpanel::PwCache::gethomedir();
}

sub _logger {
    Cpanel::LoadModule::load_perl_module('Cpanel::Logger');
    return ( $logger ||= Cpanel::Logger->new() );
}

sub _load_suspend_data {
    my ($cpusername) = @_;

    my $email_limits_file = "$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_BASE_PATH/$cpusername/$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_FILE_NAME";
    my $email_limits_str  = Cpanel::LoadFile::load_if_exists($email_limits_file);

    my $email_limits_ref;

    if ($email_limits_str) {
        try {
            $email_limits_ref = Cpanel::JSON::Load($email_limits_str);
        }
        catch {
            _logger()->warn( "The system encountered an error while reading the “$email_limits_file” file: " . Cpanel::Exception::get_string($_) );
        };
    }

    return $email_limits_ref;
}

sub _augment_popdb_with_suspend_data {

    my ( $popdbref, $cpusername ) = @_;

    my $email_limits_ref = _load_suspend_data($cpusername);

    if ($email_limits_ref) {
        foreach my $domain ( keys %$email_limits_ref ) {

            next if !$popdbref->{$domain};

            foreach my $account ( keys %{ $email_limits_ref->{$domain}{'suspended'} } ) {
                if ( $popdbref->{$domain}{'accounts'}{$account} ) {
                    $popdbref->{$domain}{'accounts'}{$account}{'suspended_outgoing'} = 1;
                }
            }

            foreach my $account ( keys %{ $email_limits_ref->{$domain}{'hold'} } ) {
                if ( $popdbref->{$domain}{'accounts'}{$account} ) {
                    $popdbref->{$domain}{'accounts'}{$account}{'hold_outgoing'} = 1;
                }
            }

        }
    }

    return;
}

sub _delete_unwanted_domains {
    my ( $popdbref, $wanted_domains_hr ) = @_;
    my @unwanted_domains = grep { index( $_, '__' ) != 0 && !exists $wanted_domains_hr->{$_} } keys %{$popdbref};
    return delete @{$popdbref}{@unwanted_domains};
}

1;
