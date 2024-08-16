package Cpanel::Admin::Base;

# cpanel - Cpanel/Admin/Base.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

#----------------------------------------------------------------------

=encoding utf-8

=head1 NAME

Cpanel::Admin::Base - base class for admin logic

=head1 SYNOPSIS

    package Cpanel::Admin::Modules::some_module;

    use parent ('Cpanel::Admin::Base');

    use constant _actions => (
        'DO_THE_THING',
    );

    # This will be called in the same context (list, scalar, or void)
    # in which the user invoked it.
    sub DO_THE_THING {
        my ($self, @args) = @_;

        # See EXCEPTIONS below.

        return $whatever;
    }

=head1 DESCRIPTION

This is a base class for admin modules that live under the
C<Cpanel::Admin::Modules::> namespace.
All such modules should subclass this module.

=head1 EXCEPTIONS

In general, an untrapped exception in an admin function will be logged
and reported to the user by only its exception ID. Thus, the user knows
that something went wrong, but the only thing they can do with that is
to inquire to the sysadmin about the failure. The sysadmin can then check
the logs to determine what happened.

While this is a sane default, it’s undesirable in some cases, e.g.,
if you tried to create a new record but an existing record conflicts
and prevents creation of the new record. For the purpose of reporting
specific errors to a caller you can either send the error back as part
of your function data, or you can create a L<Cpanel::Exception::AdminError>
instance that describes the failure; this module recognizes that class
as a special case and will send its parameters back to the user process;
that process will then reconstruct an error based on those parameters and
report it.

=head1 BACKGROUND

Originally admin functions were implemented in setuid-enabled binaries
that the user process exec()ed directly. This is problematic because of
the likelihood that a vulnerability in perl could allow unprivileged users
to muck around as root.

The binaries were then made non-setuid and executed by cpsrvd; users sent
requests to cpsrvd, and cpsrvd would send the request to the binary, then
send the response back to the user. While inefficient, it did solve the
potential-vulnerability problem.

In terms of internal construction, these binaries were basically
shell scripts that expected to receive the caller UID as an argument.
Two interfaces, “simple” and “full”, existed in parallel, and each binary
implemented one or the other interface independently of the others.
In an attempt to reduce this duplication of logic, eventually the
Cpanel::AdminBin::Script base class was created, with subclasses
::Simple and ::Full. Sometime later a third subclass, ::Call, was created
that paired with a client module, Cpanel::AdminBin::Call; this pair of
modules made it almost trivial to write new admin binaries.

A lingering problem of the ::Call binaries, however, was that all untrapped
exceptions were passed back to the user, which predisposes the system to
disclosure vulnerabilities. The inefficiency problem remained, too: cpsrvd
did a fork/exec in addition to serialization and I/O with an external
process.

This class attempts to resolve those problems with ::Call binaries.
Admin logic is no longer in “binaries” at all, but simple classes that
cpsrvd loads in at runtime. There is no I/O with an external process;
the admin function simply executes as part of cpsrvd. Additionally,
untrapped exceptions are reported only via an error ID by default.
Happily, user processes can still use the Cpanel::AdminBin::Call module.

=head1 NOTES ON ERROR REPORTING

=over

=item * Validation from the backend should not need to be sent to the
user process. If invalid parameters are given to an admin function, that
means the user process probably didn’t sufficiently validate its own
input. It is suggested that validation logic be kept in modules that
are meant to be loaded in both privileged and unprivileged processes.

=item * It is not adequate to do existence checks solely on the frontend.
This is because the system state can change between when the user process
does its existence check and when the admin process does its work. Thus,
any failure that can result from user-manageable system state
should be given back to the user.

=item * It may be easier to express user-consumable errors as part of the
function return; however, this can lead to undetected errors if a call
to your function neglects its error-checking.

=back

=head1 NOTES ON WEBMAIL

There is no centralized handling of webmail username validation;
any admin call that does something on behalf of a webmail user needs
to accept the webmail username as an argument and validate it.

=cut

#----------------------------------------------------------------------

use Cpanel::Admin::Base::Backend   ();
use Cpanel::Config::HasCpUserFile  ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Exception              ();
use Cpanel::Features::Check        ();
use Cpanel::Finally                ();
use Cpanel::PwCache                ();

#----------------------------------------------------------------------

=head1 SUBCLASS INTERFACE

Define the following in a subclass as needed:

=head2 I<OBJ>->_allowed_parents()

This defaults to a generally safe list of compiled binaries.
You can expand on this list by overriding it; you can also allow
execution from all callers by making this return the string C<*>.
B<DO> B<NOT> B<DO> B<THAT>, though, unless you absolutely I<cannot>
compile the calling code.

Notes:

=over

=item * cpsrvd, by design, forbids this list to be empty.

=item * Unless the module allows execution from all callers B<OR>
F<cpanel.config>’s C<skipparentcheck> flag is enabled, cpsrvd will
actively prevent Perl’s interpreter from calling the module.
B<THIS> B<IS> B<BY> B<DESIGN.> Having Perl’s interpreter in this list
would allow execution from all callers (since we assume unprivileged
processes can run Perl). If you I<need> that, though—and hopefully you
don’t!—then the way to do it is via C<*> as described above. There is,
thus, no reason ever to refer to a Perl interpreter in here explicitly.

=back

=cut

use constant _allowed_parents => (
    '/usr/local/cpanel/cpanel',
    '/usr/local/cpanel/uapi',
    '/usr/local/cpanel/whostmgr/bin/xml-api',
    '/usr/local/cpanel/libexec/queueprocd',
    '/usr/local/cpanel/cpsrvd',
    '/usr/local/cpanel/cpanel-email',
);

=head2 I<OBJ>->_init()

An optional callback to be executed immediately prior to the execution
of the function.

=cut

use constant _init => ();

=head2 I<OBJ>->_alarm()

The value to assign to the system alarm that ensures
no admin call runs indefinitely. (A sane default is defined.)

=cut

use constant _alarm => 350;

=head2 I<CLASS>->_actions()

Returns a list of functions that a user may call.

Any function whose name is absent from this list
will appear nonexistent to the user.

=cut

use constant _actions => ();

=head2 I<CLASS>->_actions__pass_exception()

Indicates a list of members of C<_actions()> whose untrapped
exceptions will be sent back to the user.

This is generally undesirable behavior (see
L<Cpanel::Admin::Base::ExposeExceptionsUNSAFE>), but it’s
a useful expedient to facilitate migration of modules that subclass
L<Cpanel::AdminBin::Script::Call>.

Note that for a function whose name is in this list to be callable,
that function’s name still has to be present in the list that
C<_actions()> returns.

=cut

use constant _actions__pass_exception => ();

=head2 I<CLASS>->_demo_actions()

Indicates a list of C<_actions()> members that a demo-mode user may call.
Anything not in this list is forbidden to demo-mode users.

=cut

use constant _demo_actions => ();

#----------------------------------------------------------------------

=head1 METHODS TO CALL FROM ADMIN FUNCTIONS

The following are methods that are of use to admin function authors
and maintainers:

=head2 I<OBJ>->whitelist_exceptions( \@CLASSES, $TODO_CR [, $HANDLER_CR] )

A shortcut for locally whitelisting a list of exception classes.
(@CLASSES are full Perl namespaces, e.g.,
C<Cpanel::Exception::IO::StatError>.)

Runs $TODO_CR with exceptions trapped. If the block throws,
and if the exception is an instance of any of the given @CLASSES, the
exception’s class is whitelisted. Finally, the exception is rethrown.

If no exception is thrown, then nothing is returned.
Note that $TODO_CR is called in void context.

$HANDLER_CR is optional and will receive the (rethrown) exception.
If $HANDLER_CR returns an empty list, then the exception is treated like
any other—i.e., indicated to the user solely by ID. Otherwise,
$HANDLER_CR’s returns are given as the arguments to create a
L<Cpanel::Exception::AdminError> instance, which determines what
description of the failure the user will actually receive in response.

If $HANDLER_CR is not given, then the error’s class, ID, stringified
form, and metadata are returned to the user.
For L<Cpanel::Exception> instances, the stringified
form is the error’s C<to_locale_string_no_id()> return value.

For example:

    $self->whitelist_exceptions(
        [ 'X::AlwaysSafeForUsers' ],
        \&_might_throw_x_alwayssafeforusers
    );

    $self->whitelist_exceptions(
        [ 'X::FooBar' ],
        \&_might_throw_x_foobar,
        sub {
            my ($err) = @_;

            my @ret;

            if ($err->is_safe_for_user()) {

                # See Cpanel::Exception::AdminError’s documentation
                # for the arguments that can be given here.
                @ret = ( message => $err->to_string() );
            }

            return @ret;
        },
    );

=cut

sub whitelist_exceptions ( $self, $classes_ar, $todo_cr, $handler_cr = undef ) {    ## no critic qw(Proto ManyArgs)

    local $@;

    if ( !eval { $todo_cr->(); 1 } ) {
        if ( my $class = ref $@ ) {
            if ( grep { $class->isa($_) } @$classes_ar ) {
                $self->{'_on_exception'}{$class} = $handler_cr;
            }
        }

        die;
    }

    return;
}

=head2 I<OBJ>->whitelist_exception( $CLASS [ => $HANDLER_CR ] )

A simpler interface than C<whitelist_exceptions()> that whitelists
a single exception class B<permanently>. The normal use case is to call
this immediately prior to a C<die()>. Use with caution; if in doubt,
prefer C<whitelist_exceptions()>.

=cut

sub whitelist_exception ( $self, $class, $handler_cr = undef ) {
    $self->{'_on_exception'}{$class} = $handler_cr;

    return $self;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->get_passed_fh()

Returns the filehandle, if any, that the caller submitted with the request.

=cut

sub get_passed_fh {
    return $_[0]->{'passed_fh'};
}

#----------------------------------------------------------------------

=head2 $fn = I<OBJ>->get_action()

Returns the name of the function that the user called (e.g., C<GETZONE>).

=cut

sub get_action {
    return $_[0]->{'function'};
}

#----------------------------------------------------------------------

=head2 $domain = I<OBJ>->get_cpuser_domain()

Returns the caller’s primary domain.

=cut

sub get_cpuser_domain {
    my ($self) = @_;

    my $cpuser = $self->_get_caller_cpuser_data();

    return $cpuser->{'DOMAIN'};
}

#----------------------------------------------------------------------

=head2 $domains_ar = I<OBJ>->get_cpuser_domains()

Returns the caller’s current “created” domains—i.e., those that appear
in the user’s cpuser file.

=cut

sub get_cpuser_domains {
    my ($self) = @_;

    my $cpuser = $self->_get_caller_cpuser_data();

    return [ $cpuser->{'DOMAIN'}, @{ $cpuser->{'DOMAINS'} } ];
}

#----------------------------------------------------------------------

=head2 $domains_ar = I<OBJ>->get_cpuser_former_domains_that_remain_unused()

Returns the caller’s “created” domains that the caller formerly used
but now are unused.

=cut

sub get_cpuser_former_domains_that_remain_unused {
    my ($self) = @_;

    my $cpuser = $self->_get_caller_cpuser_data();

    return [ @{ $cpuser->{'DEADDOMAINS'} } ];
}

#----------------------------------------------------------------------

=head2 $uid = I<OBJ>->get_cpuser_uid()

Returns the caller’s UID.

=cut

sub get_cpuser_uid {
    my ($self) = @_;

    return $self->{'caller'}{'_uid'};
}

#----------------------------------------------------------------------

=head2 $name = I<OBJ>->get_caller_username()

Returns the caller’s username.

=cut

sub get_caller_username {
    my ($self) = @_;

    return $self->{'caller'}{'_username'};
}

#----------------------------------------------------------------------

=head2 $dir = I<OBJ>->get_cpuser_homedir()

Returns the caller’s homedir.

=cut

sub get_cpuser_homedir {
    my ($self) = @_;

    return $self->{'caller'}{'_homedir'};
}

#----------------------------------------------------------------------

=head2 I<OBJ>->verify_that_cpuser_owns_domain( $DOMAIN )

Throws an exception if the caller does not own $DOMAIN.
It should either be fixed or avoided in new code; see C<cpuser_owns_domain()>.

=cut

sub verify_that_cpuser_owns_domain {
    if ( !$_[0]->cpuser_owns_domain( $_[1] ) ) {
        die _user_err( _locale()->maketext( '“[_1]” is not a domain that you own.', $_[1] ) );
    }

    return 1;
}

#----------------------------------------------------------------------

=head2 $yn = I<OBJ>->cpuser_owns_domain( $DOMAIN )

Indicates, by an overly-simple deduction, whether the caller owns
$DOMAIN. This does not take account for all auto-subdomains (e.g., C<mail.>)
and thus should either be fixed or avoided in new code.

=cut

sub cpuser_owns_domain {
    my ( $self, $domain ) = @_;

    #Cache this for the sake of code that runs this logic
    #in a tight loop.
    if ( !$self->{'_domains_lookup'} ) {
        my $domains_ar = $self->get_cpuser_domains();
        @{ $self->{'_domains_lookup'} }{@$domains_ar} = ();
    }

    substr( $domain, 0, 4, '' ) if rindex( $domain, 'www.', 0 ) == 0;

    return exists $self->{'_domains_lookup'}{$domain};
}

#----------------------------------------------------------------------

=head2 $yn = I<OBJ>->cpuser_has_feature( $FEATURE_NAME )

Indicates whether the caller has access to the given feature.

=cut

sub cpuser_has_feature {
    my ( $self, $feature ) = @_;
    my $cpuser_data_ref = $self->_get_caller_cpuser_data();
    return Cpanel::Features::Check::check_feature_for_user(
        $self->get_caller_username(),
        $feature,
        $cpuser_data_ref->{FEATURELIST},
        $cpuser_data_ref,
    );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->cpuser_has_feature_or_die( $FEATURE_NAME )

Throws a L<Cpanel::Exception::AdminError> with an appropriate message
if the user lacks the given feature.

=cut

sub cpuser_has_feature_or_die {
    my ( $self, $feature ) = @_;

    return if $self->cpuser_has_feature($feature);

    require Cpanel::Features;

    my %feature_desc = map { $_->[0] => $_->[1] } Cpanel::Features::load_feature_descs();

    die _user_err( _locale()->maketext( 'Your hosting provider must enable the “[_1]” feature to perform this action.', $feature_desc{$feature} // $feature ) );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->cpuser_has_all_of_features_or_die( @FEATURE_NAMES )

Throws a L<Cpanel::Exception::AdminError> with an appropriate message
if the calling cpuser lacks any of the given features.

=cut

sub cpuser_has_all_of_features_or_die {
    my ( $self, @features ) = @_;

    my @missing_feature = grep { not $self->cpuser_has_feature($_) } @features;
    return if not @missing_feature;

    require Cpanel::Features;
    my %feature_desc = map { $_->[0] => $_->[1] } Cpanel::Features::load_feature_descs();

    die _user_err(
        _locale()->maketext(
            'Your hosting provider must enable the [list_and_quoted,_1] [numerate,_2,feature,features] to perform this action.',
            [ map { $feature_desc{$_} // $_ } @missing_feature ],
            scalar @missing_feature,
        )
    );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->cpuser_has_at_least_one_of_features_or_die( @FEATURE_NAMES )

Throws a L<Cpanel::Exception::AdminError> with an appropriate message
if the user lacks all of the given features.

=cut

sub cpuser_has_at_least_one_of_features_or_die {
    my ( $self, @features ) = @_;

    my @missing_feature;
    for my $feature (@features) {
        return if $self->cpuser_has_feature($feature);
        push @missing_feature, $feature;
    }

    require Cpanel::Features;
    my %feature_desc = map { $_->[0] => $_->[1] } Cpanel::Features::load_feature_descs();

    die _user_err( _locale()->maketext( 'Your hosting provider must enable the [list_or_quoted,_1] feature to perform this action.', [ map { $feature_desc{$_} // $_ } @missing_feature ] ) );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->verify_that_cpuser_has_subaccount( $username, $domain )

This function provides equivalent functionality to the
L<Cpanel::AdminBin::Script::verify_that_caller_has_subaccount> method.

Throws a L<Cpanel::Exception::AdminError> with an appropriate message
if the user does not possess the given subaccount.

Note that this method will also call L<verify_that_cpuser_owns_domain>
on the provided domain before querying the cpuser’s subaccounts.

=cut

sub verify_that_cpuser_has_subaccount {

    my ( $self, $username, $domain ) = @_;

    require Cpanel::Validate::VirtualUsername;
    my $full_username = $username . '@' . $domain;
    Cpanel::Validate::VirtualUsername::validate_or_die($full_username);    # just in case an adminbin doesn't do this step itself before calling this method

    # Don’t bother deescalating and querying the UserManager DB if the
    # cpuser doesn’t even own the domain.
    $self->verify_that_cpuser_owns_domain($domain);

    require Cpanel::AccessIds;
    require Cpanel::UserManager::Storage;

    # This must use Cpanel::AccessIds::do_as_user instead of
    # Cpanel::AccessIds::ReducedPrivileges::call_as_user since the underlying
    # call accesses SQLite and there are concerns with being able to reescalate
    # back to root.
    my $has_user = Cpanel::AccessIds::do_as_user(
        $self->get_caller_username(),
        sub {
            my $user = Cpanel::UserManager::Storage::lookup_user(
                username => $username,
                domain   => $domain,
            );
            return $user ? 1 : 0;
        },
    );

    die _user_err( _locale()->maketext( 'The “[_1]” subaccount does not exist.', "$username\@$domain" ) ) if !$has_user;

    return 1;
}

=head1 SERVER INTERFACE

These methods are meant to be called only from within cpsrvd’s
admin handler logic.

=head2 I<CLASS>->run( %OPTS )

The main entry point into this module. %OPTS are:

=over

=item * C<uid> - i.e., of the caller

=item * C<function> (i.e., “action”, the name the function to run)

=item * C<args> - array reference

=item * C<wantarray> - The value of C<wantarray()> from the caller’s
context. The C<function> will run in the corresponding context.

=item * C<passed_fh> - The filehandle, if any, that the user passed.

=back

The return is a reference to either a plain scalar (e.g., \'Hi')
or an array reference (e.g., \[ 1, 2, 3 ]), depending on C<wantarray>.

=cut

sub run {
    my ( $class, %opts ) = @_;

    my $self = bless \%opts, $class;

    my ( $uid, $function, $args_ar ) = @opts{ 'uid', 'function', 'args' };

    die 'No nonzero “uid” given!' if !$uid;

    die 'Need “function”!' if !$function;

    die "“args” must be an ARRAY reference, not “$args_ar”!" if !UNIVERSAL::isa( $args_ar, 'ARRAY' );

    my ( $username, $homedir ) = ( Cpanel::PwCache::getpwuid($uid) )[ 0, 7 ];

    if ( !$username ) {
        die "Unrecognized UID: “$uid”";
    }

    if ( $username ne 'cpanel' && ( $username eq 'root' || !Cpanel::Config::HasCpUserFile::has_cpuser_file($username) ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” ([asis,UID] “[_2]”) is not a valid user for this module.', [ $username, $uid ] );
    }
    my ( $team_user, $team_login_domain );
    if ( $ENV{'TEAM_USER'} || $ENV{'TEAM_LOGIN_DOMAIN'} ) {
        $self->_verify_team_owner_owns_login_domain( $ENV{'TEAM_LOGIN_DOMAIN'}, $username );
        $self->_verify_if_team_user_exists( $ENV{'TEAM_USER'}, $ENV{'TEAM_LOGIN_DOMAIN'} );
        $team_user         = $ENV{'TEAM_USER'};
        $team_login_domain = $ENV{'TEAM_LOGIN_DOMAIN'};
    }

    $self->{'caller'} = {
        _uid                    => $uid,
        _username               => $username,
        _homedir                => $homedir,
        _team_user              => $team_user,
        _team_user_login_domain => $team_login_domain,
    };

    my $ok = eval {
        my $fn_exists = $self->can($function) && grep { $_ eq $function } $self->_actions();

        if ( !$fn_exists ) {
            my $module = ref $self;
            die Cpanel::Exception::create_raw( 'InvalidParameter', "Missing or invalid function in $module: $function" );
        }

        if ( $self->_get_caller_cpuser_data()->{'DEMO'} ) {
            if ( !grep { $_ eq $function } $self->_demo_actions() ) {
                die Cpanel::Exception::create('ForbiddenInDemoMode');
            }
        }

        1;
    };

    # The above two errors are both ones that we want to
    # send back to the caller.
    if ( !$ok ) {
        Cpanel::Admin::Base::Backend::process_exception_whitelist(
            $@,
            { ref($@) => undef },
        );
    }

    #----------------------------------------------------------------------

    my $max_run_time = $self->_alarm();
    alarm $max_run_time;

    my $reset_alarm = Cpanel::Finally->new( sub { alarm 0 } );

    # Initialization defined by the script.
    $self->_init();

    my $ret;

    local $self->{'_on_exception'};

    local $@;

    if ( defined $opts{'wantarray'} ) {
        eval { $ret = [ $opts{'wantarray'} ? $self->$function(@$args_ar) : scalar $self->$function(@$args_ar) ] };
    }
    else {
        eval {
            $self->$function(@$args_ar);
            $ret = [];
        };
    }

    if ( !$ret ) {
        my $err = $@;

        my $pass_any_untrapped_exception_to_caller = grep { $_ eq $function } $self->_actions__pass_exception();

        if ($pass_any_untrapped_exception_to_caller) {
            die $err if eval { $err->isa('Cpanel::Exception::AdminError') };

            require Cpanel::Admin::Base::ExposeExceptionsUNSAFE;
            my ( $id, $class, $str ) = Cpanel::Admin::Base::ExposeExceptionsUNSAFE::handle_untrapped_exception($err);
            my $new_err = Cpanel::Exception::create( 'AdminError', [ class => $class, message => $str ] );
            $new_err->set_id($id);

            die $new_err;
        }

        if ( $self->{'_on_exception'} && _is_blessed($err) ) {
            Cpanel::Admin::Base::Backend::process_exception_whitelist(
                $err,
                $self->{'_on_exception'},
            );
        }

        local $@ = $err;
        die;
    }

    return $ret;
}

sub _is_blessed {

    # Lighter than Scalar::Util::blessed().
    return UNIVERSAL::isa( $_[0], 'UNIVERSAL' );
}

#----------------------------------------------------------------------

=head2 I<CLASS>->ALLOWED_PARENTS()

Returns the C<_allowed_parents()> list.

=cut

sub ALLOWED_PARENTS {
    my ($self) = @_;

    return $self->_allowed_parents();
}

=head2 I<CLASS>->handle_untrapped_exception( $ERROR )

This method is to be called from the server module, not from subclasses.
It takes in an untrapped exception and returns a user-process-appropriate
error ID, exception class, and message.

By default, the user receives merely the error ID, and the message just
reiterates that error ID. L<Cpanel::Exception::AdminError> instances,
though, are treated differently: the C<class>, C<message>, and C<metadata>
are given to the user. This mechanism allows tagging specific errors
as appropriate to give to the caller.

=cut

sub handle_untrapped_exception {
    my ( undef, $err ) = @_;

    my ( $err_id, $err_class, $err_string, $err_metadata );

    # Cpanel::Exception::AdminError errors specifically indicate
    # errors to give to the user. Any other error is one that we
    # report to the user only via exception ID.

    if ( UNIVERSAL::isa( $err, 'Cpanel::Exception::AdminError' ) ) {
        $err_class = $err->get('class');

        $err_string = $err->get('message') || do {
            warn("AdminError exception created with no “message”??");
            'Unknown error';
        };

        $err_id = $err->id();

        $err_metadata = $err->get('metadata');
    }
    else {
        if ( !UNIVERSAL::isa( $err, 'Cpanel::Exception' ) ) {
            require Cpanel::Exception;
            $err = Cpanel::Exception->create_raw("$err");
        }

        $err_id = $err->id();

        $err_string = _locale()->maketext_plain_context( 'The request failed. (Error ID: [_1]) Ask your hosting provider to research this error in [asis,cPanel amp() WHM]’s main error log.', $err_id );

        local $@ = $err;
        warn;
    }

    return ( $err_id, $err_class, $err_string, $err_metadata );
}

#----------------------------------------------------------------------

=head2 $name = I<OBJ>->get_caller_team_user()

Returns the Team_user's username.

=cut

sub get_caller_team_user {
    my ($self) = @_;
    $self->_verify_if_team_user_exists( $ENV{'TEAM_USER'}, $ENV{'TEAM_LOGIN_DOMAIN'} );

    return $self->{'caller'}{'_team_user'};
}

#----------------------------------------------------------------------

=head2 $name = I<OBJ>->get_caller_team_user_login_domain()

Returns the domain the team-user logged in with.

=cut

sub get_caller_team_user_login_domain {
    my ($self) = @_;
    $self->_verify_team_owner_owns_login_domain( $ENV{'TEAM_LOGIN_DOMAIN'}, $self->get_caller_username() );

    return $self->{'caller'}{'_team_user_login_domain'};
}

#----------------------------------------------------------------------

my $locale;

sub _locale {
    local ( $@, $! );
    require Cpanel::Locale;
    return $locale ||= Cpanel::Locale->get_handle();
}

sub _user_err {
    my ($str) = @_;

    return Cpanel::Exception::create(
        'AdminError',
        [ message => $str ],
    );
}

sub _get_caller_cpuser_data {
    my ($self) = @_;

    #NOTE: We'll need to break this cache if domains are added/removed.
    $self->{'caller'}{'_cpuser_data'} ||= Cpanel::Config::LoadCpUserFile::load( $self->get_caller_username() );

    if ( !$self->{'caller'}{'_cpuser_data'} ) {
        die _user_err(
            _locale()->maketext( 'An unknown error prevented the system from loading [_1]’s information.', $self->get_caller_username() ),
        );
    }

    return $self->{'caller'}{'_cpuser_data'};
}

sub _verify_team_owner_owns_login_domain {
    my ( $self, $team_login_domain, $username ) = @_;
    require Cpanel::AcctUtils::DomainOwner;
    if ( !Cpanel::AcctUtils::DomainOwner::is_domain_owned_by( $team_login_domain, $username ) ) {
        die Cpanel::Exception::create( 'DomainOwnership', 'You do not own the domain “[_1]”.', [$team_login_domain] );
    }

    return 1;
}

sub _verify_if_team_user_exists {
    my ( $self, $team_user, $team_login_domain ) = @_;
    require Cpanel::Team::Config;
    if ( not my $team_owner = Cpanel::Team::Config::get_team_info( $team_user, $team_login_domain )->{'owner'} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The team user “[_1]” does not exist.', [$team_user] );
    }

    return 1;
}
1;
