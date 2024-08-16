package Cpanel::AdminBin::Script;

# cpanel - Cpanel/AdminBin/Script.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::Exit                      ();
use Cpanel::AdminBin::Serializer      ();
use Cpanel::Config::LoadCpUserFile    ();
use Cpanel::ConfigFiles               ();
use Cpanel::Exception                 ();
use Cpanel::Features::Check           ();
use Cpanel::LoadModule                ();
use Cpanel::Locale                    ();
use Cpanel::Locale::Utils::User       ();
use Cpanel::PwCache                   ();
use Cpanel::PwCache::Helpers          ();
use Cpanel::PwDiskCache               ();
use Cpanel::LoadModule                ();
use Cpanel::BinCheck::Lite            ();
use Cpanel::Validate::VirtualUsername ();

my $PACKAGE = __PACKAGE__;

my $DEFAULT_MAX_RUN_TIME = 350;

#----------------------------------------------------------------------
#NOTE: Do not instantiate this class or subclass it directly;
#instead, subclass the "Call" subclass.
#----------------------------------------------------------------------

#Script's specific init steps. Called immediately before the "action".
sub _init { }

#Returns a list of valid actions.
sub _actions {
    CORE::die "Abstract method ${PACKAGE}::_actions should not be called!";
    return;    #perlcritic
}

#Sets 'uid', 'action', and 'arguments' properties.
#("Simple" and "Full" subclasses take care of this.)
sub _init_uid_action_arguments {
    CORE::die "Abstract method ${PACKAGE}::_init_uid_action_arguments should not be called!";
    return;    #perlcritic
}

#Optional; allows admin actions for demo mode.
sub _demo_actions { }

#----------------------------------------------------------------------

#Subclasses may override if print/exit() is not desired.
#XXX: Do NOT call this directly from tests. While that was the original
#intent of this method, it turns out that a simple die() avoids some
#thorny liabilities of the design of this framework.
*die = \&_exit_EPERM;

#Same as new() but looks for '--bincheck' as the first @ARGV member;
#if it's there, we print an "ok" line then exit.
#
#Use this to run as a script, e.g.:
#   __PACKAGE__->run( alarm => NNN )
#
#opts (named) are:
#   - alarm: Number of seconds before an ALRM signal kills this process.

sub run {
    my ( $class, @opts ) = @_;

    Cpanel::BinCheck::Lite::check_argv();

    $class->new(@opts);

    return Cpanel::Exit::exit_with_stdout_closed_first();
}

sub _check_if_stack_has_eval_after_new {
    my $n = 1;    #We know *this* function isn't an eval!
    while ( my @caller_info = caller $n ) {
        my ( $package, $subroutine ) = @caller_info[ 0, 3 ];
        return 1 if $subroutine eq '(eval)';
        last     if $package eq __PACKAGE__ && $subroutine eq __PACKAGE__ . '::new';

        $n++;
    }

    return 0;
}

#Use this if you load the script as a modulino.
#opts are the same as for run().
sub new {
    my ( $class, %opts ) = @_;

    my $self = bless { _start_pid => $$ }, $class;

    #It's much simpler to allow admin functions to die()
    #rather than requiring them to call $self->die().
    local $SIG{'__DIE__'} = sub {

        #We can't just check $^S since tests often execute within an eval.
        #So, we need a specific check of whether eval is part of the stack
        #*after* this module's constructor function.
        return if _check_if_stack_has_eval_after_new();

        $self->_catch_die(@_);
    };

    local $SIG{'ALRM'} = sub {
        $self->exit( 'ETIMEDOUT', 'Timeout: Alarm' );
    };

    my $max_run_time = $opts{'alarm'} || $DEFAULT_MAX_RUN_TIME;
    alarm $max_run_time;

    my %SECURE_PWCACHE;
    tie %SECURE_PWCACHE, 'Cpanel::PwDiskCache';
    Cpanel::PwCache::Helpers::init( \%SECURE_PWCACHE );

    $self->_init_uid_action_arguments();

    my $uid = $self->get_caller_uid();

    if ( !length $uid || $uid !~ m{^[0-9]+$} ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [output,abbr,UID,User identifier].', [$uid] );
    }

    my $action = $self->get_action();

    my ( $user, $homedir ) = ( Cpanel::PwCache::getpwuid($uid) )[ 0, 7 ];

    #This is here to ensure that the localization on the admin side
    #matches that from userland.
    #FIXME: Find a better way of doing this.
    local $Cpanel::CPDATA{'LOCALE'} = Cpanel::Locale::Utils::User::get_user_locale($user);

    @{ $self->{'caller'} }{qw( _username  _homedir )} = ( $user, $homedir );

    if ( $user ne 'cpanel' && ( !$user || $user eq 'root' || !-e "$Cpanel::ConfigFiles::cpanel_users/$user" ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” ([asis,UID] “[_2]”) is not a valid user for this module.', [ $user, $uid ] );
    }

    if ( $self->_get_caller_cpuser_data()->{'DEMO'} ) {
        my @valid_actions = $self->_demo_actions();
        if ( !grep { $_ eq $action } @valid_actions ) {
            die Cpanel::Exception::create('ForbiddenInDemoMode');
        }
    }
    else {
        my @valid_actions = $self->_actions();
        if ( !grep { $_ eq $action } @valid_actions ) {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid action for this module.', [$action] );
        }
    }

    #Initialization defined by the script.
    $self->_init();

    $self->_return_admin_payload( $self->_dispatch_method() );

    #We'll only get here when return() is overridden.
    alarm 0;

    return $self;
}

#For subclasses to override.
sub _dispatch_method {
    my ($self) = @_;

    my $method = $self->get_action();

    return $self->$method();
}

#For subclasses to override.
sub _catch_die {
    my ( $self, @args ) = @_;

    if ( scalar(@args) == 1 && try { $args[0]->isa('Cpanel::Exception') } ) {
        $self->die( $args[0]->to_locale_string() );
    }

    return $self->die(@args);
}

sub _exit_EPERM {
    my ( $self, @args ) = @_;

    $self->exit( 'EPERM', @args );

    exit 1;
}

#Same as die(), but the first argument is either:
#   1) the exit code name (from the Errno core module)
#   2) the exit code number
#
#Any subsequent args are printed to STDOUT (i.e., an error message).
sub exit {
    my ( $self, $err, @args ) = @_;

    my $err_ok;
    if ( length $err ) {

        # leave it alone if it's already numeric.
        if ( $err !~ tr{0-9}{}c ) {
            $err_ok = 1;
        }

        # Try to convert the error to the Errno equivalent.
        else {
            require Errno;
            if ( my $ev = Errno->can($err) ) {
                $err    = $ev->();
                $err_ok = 1;
            }
        }
    }

    if ( !$err_ok ) {
        push @args, "“$err” is not a valid error code.";
        require Errno;
        $err = Errno::EPERM();
    }

    if ( length $args[-1] && substr( $args[-1], -1 * length $/ ) ne $/ ) {
        $args[-1] .= $/;
    }

    print @args;

    CORE::exit $err;

    return;    #for PerlCritic
}

#Subclasses may override if print/exit() is not desired.
sub _return_admin_payload {    ##no critic qw(RequireArgUnpacking)
    my ( $self, $args_ar ) = ( shift, \@_ );    #avoid a scalar copy.

    my $payload_r;

    if ( @$args_ar == 1 ) {
        $payload_r = \$args_ar->[0];
        $payload_r = $$payload_r if ref $$payload_r;
    }
    elsif (@$args_ar) {
        $payload_r = $args_ar;
    }

    if ( defined $payload_r ) {
        if ( ref $payload_r eq 'SCALAR' ) {
            if ( length $$payload_r ) {
                print $$payload_r or $self->die($!);
            }
        }
        else {
            print ".\n" or $self->die($!);

            open my $stdout, '>&=STDOUT' or $self->die($!);

            try {
                Cpanel::AdminBin::Serializer::DumpFile( $stdout, $payload_r );
            }
            catch {
                $self->_exit_EPERM($_);
            };
        }
    }

    #This fixed a segfault when running the postgresql module forked from a test
    #that runs under Devel::Cover. The segfaults appear to be from DBI handles
    #referred to in a Cpanel::PostgresAdmin object. (NOTE: disconnect()ing and
    #destroying the DBI handles in Cpanel::PostgresAdmin::DESTROY() did not
    #resolve the issue.)
    #
    #While that may be an isolated incident, there have been other modules that
    #do funny things on global destruction, so we might as well preempt those
    #problems here.
    %$self = ();

    return CORE::exit 0;
}

sub _get_caller_cpuser_data {
    my ($self) = @_;

    #NOTE: We'll need to break this cache if domains are added/removed.
    $self->{'caller'}{'_cpuser_data'} ||= Cpanel::Config::LoadCpUserFile::load( $self->get_caller_username() );

    if ( !$self->{'caller'}{'_cpuser_data'} ) {
        CORE::die Cpanel::Exception->create( 'An unknown error prevented the system from loading [_1]’s information.', [ $self->get_caller_username() ] );
    }

    return $self->{'caller'}{'_cpuser_data'};
}

sub reset_cpuser_data {
    my ($self) = @_;

    delete $self->{'caller'}{'_cpuser_data'};

    delete $self->{'_domains_lookup'};

    return;
}

sub get_caller_domain {
    my ($self) = @_;

    my $cpuser = $self->_get_caller_cpuser_data();

    return $cpuser->{'DOMAIN'};
}

sub get_caller_domains {
    my ($self) = @_;

    my $cpuser = $self->_get_caller_cpuser_data();

    return [ $cpuser->{'DOMAIN'}, @{ $cpuser->{'DOMAINS'} } ];
}

sub get_caller_former_domains_that_remain_unused {
    my ($self) = @_;

    my $cpuser = $self->_get_caller_cpuser_data();

    return [ @{ $cpuser->{'DEADDOMAINS'} } ];
}

sub get_caller_uid {
    my ($self) = @_;

    return $self->{'caller'}{'_uid'};
}

sub get_caller_username {
    my ($self) = @_;

    return $self->{'caller'}{'_username'};
}

sub get_caller_homedir {
    my ($self) = @_;

    return $self->{'caller'}{'_homedir'};
}

sub get_arguments {
    my ($self) = @_;

    return [ @{ $self->{'_arguments'} } ];
}

sub get_action {
    my ($self) = @_;

    return $self->{'_action'};
}

sub verify_that_caller_owns_domain {
    if ( !$_[0]->caller_owns_domain( $_[1] ) ) {
        die( _locale()->maketext( '“[_1]” is not a domain that you own.', $_[1] ) );
    }

    return 1;
}

sub caller_owns_domain {
    my ( $self, $domain ) = @_;

    #Cache this for the sake of code that runs this logic
    #in a tight loop.
    if ( !$self->{'_domains_lookup'} ) {
        my $domains_ar = $self->get_caller_domains();
        @{ $self->{'_domains_lookup'} }{@$domains_ar} = ();
    }

    substr( $domain, 0, 4, '' ) if rindex( $domain, 'www.', 0 ) == 0;

    return exists $self->{'_domains_lookup'}{$domain};
}

sub verify_that_caller_has_subaccount {
    my ( $self, $mailbox, $domain ) = @_;

    if ( !$self->caller_has_subaccount( $mailbox, $domain ) ) {
        die( _locale()->maketext( 'The “[_1]” subaccount does not exist.', $mailbox . '@' . $domain ) );
    }

    return 1;
}

sub caller_has_subaccount {
    my ( $self, $mailbox, $domain ) = @_;

    my $full_username = $mailbox . '@' . $domain;
    Cpanel::Validate::VirtualUsername::validate_or_die($full_username);    # just in case an adminbin doesn't do this step itself before calling this method

    # Loading in the parent so it will only load once rather then
    # once for each child process in the do_as_user().
    Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds');    # TODO:  can Cpanel::AccessIds::ReducedPrivileges be be used here?
    Cpanel::LoadModule::load_perl_module('Cpanel::UserManager::Storage');

    return Cpanel::AccessIds::do_as_user(
        $self->get_caller_username(),
        sub {
            my $user = Cpanel::UserManager::Storage::lookup_user(
                username => $mailbox,
                domain   => $domain,
            );
            return $user ? 1 : 0;
        }
    );
}

sub _read_first_line {
    my ($self) = @_;

    my $line1 = readline \*STDIN;
    chomp $line1;

    return [ split m{\s+}, $line1 ];
}

sub user_has_feature {
    my ( $self, $feature ) = @_;
    my $cpuser_data_ref = $self->_get_caller_cpuser_data();
    return Cpanel::Features::Check::check_feature_for_user(
        $self->get_caller_username(),
        $feature,
        $cpuser_data_ref->{FEATURELIST},
        $cpuser_data_ref,
    );
}

sub user_has_feature_or_die {
    my ( $self, $feature ) = @_;

    return if $self->user_has_feature($feature);
    Cpanel::LoadModule::load_perl_module('Cpanel::Features');
    my %feature_desc = map { $_->[0] => $_->[1] } Cpanel::Features::load_feature_descs();
    die Cpanel::Exception->create(
        'Your hosting provider must enable the “[_1]” feature to perform this action.',
        [ exists $feature_desc{$feature} ? $feature_desc{$feature} : $feature ],
    );
}

sub user_has_all_of_features_or_die {
    my ( $self, @features ) = @_;

    my @missing_feature = grep { not $self->user_has_feature($_) } @features;
    return if not @missing_feature;

    Cpanel::LoadModule::load_perl_module('Cpanel::Features');
    my %feature_desc = map { $_->[0] => $_->[1] } Cpanel::Features::load_feature_descs();
    die Cpanel::Exception->create(
        'Your hosting provider must enable the [list_and_quoted,_1] [numerate,_2,feature,features] to perform this action.',
        [
            [ map { exists $feature_desc{$_} ? $feature_desc{$_} : $_ } @missing_feature ],
            scalar @missing_feature,
        ],
    );
}

sub user_has_at_least_one_of_features_or_die {
    my ( $self, @features ) = @_;

    my @missing_feature;
    for my $feature (@features) {
        return if $self->user_has_feature($feature);
        push @missing_feature, $feature;
    }
    Cpanel::LoadModule::load_perl_module('Cpanel::Features');
    my %feature_desc = map { $_->[0] => $_->[1] } Cpanel::Features::load_feature_descs();
    die Cpanel::Exception->create(
        'Your hosting provider must enable the [list_or_quoted,_1] feature to perform this action.',
        [ [ map { exists $feature_desc{$_} ? $feature_desc{$_} : $_ } @missing_feature ] ],
    );
}

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

1;
