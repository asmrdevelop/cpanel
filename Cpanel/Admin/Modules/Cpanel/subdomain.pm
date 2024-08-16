package Cpanel::Admin::Modules::Cpanel::subdomain;

# cpanel - Cpanel/Admin/Modules/Cpanel/subdomain.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw( Cpanel::Admin::Base );

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::subdomain

=head1 DESCRIPTION

This module includes admin logic for management of subdomains/vhosts.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Autodie                      ();
use Cpanel::Config::LoadCpUserFile       ();
use Cpanel::Exception                    ();
use Cpanel::Hostname                     ();
use Cpanel::PHPFPM::Constants            ();
use Cpanel::RedirectFH                   ();
use Cpanel::Sub                          ();
use Cpanel::SubDomain::Create            ();
use Cpanel::Try                          ();
use Cpanel::Validate::DocumentRoot       ();

# XXX Please don’t add to this list.
use constant _actions__pass_exception => (
    'CHANGEDOCROOT',
    'ADD',
    'DEL',
);

# Add to this list instead.
use constant _actions => (
    _actions__pass_exception(),
);

#----------------------------------------------------------------------

=head2 $resp_hr = ADD( %opts )

Adds a subdomain/vhost.

%opts are:

=over

=item * C<rootdomain> - The base domain.

=item * C<subdomain> - The subdomain B<PART>. This is B<not> the full domain.

=item * C<documentroot> - The directory to use as the new vhost’s docroot.

=item * C<force> - Passed to C<Cpanel::Sub::addsubdomain()>.

=item * C<usecannameoff> - boolean, whether to disable C<UseCanonicalName>
in the new vhost’s configuration

=item * C<skip_restart_apache> - boolean

=item * C<skip_phpfpm> - boolean

=back

The return is a hash reference of:

=over

=item * C<message> - A human-readable message that describes what happened.
See C<Cpanel::Sub::addsubdomain()>.

=item * C<documentroot> - The new vhost’s document root. This may or may
not match what was given in %opts because we massage that input (i.e.,
rather than rejecting it outright).

=back

=cut

sub ADD ( $self, %opts ) {
    my $skip_ssl_setup = $opts{'skip_ssl_setup'} ? 1 : 0;

    _validate_domain_or_die( $opts{'rootdomain'} );
    _validate_domain_or_die( $opts{'subdomain'} );

    $self->_validate_domain_ownership( $opts{'rootdomain'} );

    # This *may* be redundant with checks performed further down the line,
    # but this is logic that was part of the old domain.pl admin binary,
    # so we preserve it here.
    require Cpanel::Validate::SubDomain;
    if ( !Cpanel::Validate::SubDomain::is_valid( $opts{'subdomain'} ) ) {
        die _invalid_parameter( locale()->maketext( 'The subdomain “[_1]” is not valid.', $opts{'subdomain'} ) );
    }

    _validate_dir_or_die( $opts{'documentroot'} );

    if ( $opts{'subdomain'} eq 'subdomainip' ) {
        die _invalid_parameter("“subdomainip” is a reserved word and cannot be used as a subdomain.");
    }

    my $full_domain_name = $opts{'subdomain'} . '.' . $opts{'rootdomain'};

    _die_if_equals_hostname($full_domain_name);

    my $cpuser = $self->_get_cpuser_data();

    my $maxsub =
      !length( $cpuser->{'MAXSUB'} ) || $cpuser->{'MAXSUB'} =~ m/unlimited/i
      ? 'unlimited'
      : int $cpuser->{'MAXSUB'};

    if ( $maxsub ne 'unlimited' && $maxsub <= $self->_countsubdomains() ) {
        die Cpanel::Exception::create(
            'AdminError',
            [
                message => locale()->maketext('You have exceeded the maximum allowed subdomains.'),
            ],
        );
    }

    if ( $opts{'subdomain'} =~ /^www\.?$/i ) {
        die _invalid_parameter( locale()->maketext('The system cannot change the master entry [asis,www].') );
    }

    my $docroot = $opts{'documentroot'};

    if ( Cpanel::Autodie::exists($docroot) ) {
        if ( !-d _ ) {
            die Cpanel::Exception::create(
                'AdminError',
                [
                    message => locale()->maketext( '“[_1]” is not a directory.', $docroot ),
                ]
            );
        }
    }
    else {
        $docroot = $self->get_cpuser_homedir() . "/public_html/$opts{'subdomain'}";
    }

    # REMOTE_USER needs to be set to the reseller for DNS cluster configuration
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my $fn = $opts{'skip_phpfpm'} ? 'create_without_phpfpm_setup' : 'create_with_phpfpm_setup';

    my ( $ok, $result ) = Cpanel::SubDomain::Create->can($fn)->(
        @opts{ 'subdomain', 'rootdomain' },

        skip_ssl_setup => ( $skip_ssl_setup ? 1 : 0 ),
        documentroot   => $docroot,
        user           => $self->get_caller_username(),

        %opts{
            'force',
            'usecannameoff',
            'skip_restart_apache',
        },
    );

    die $result if !$ok;

    return {
        message      => $result,
        documentroot => $docroot,
    };
}

sub _countsubdomains ($self) {
    my $username = $self->get_caller_username();

    require Cpanel::Config::WebVhosts;
    my $vhsconf = Cpanel::Config::WebVhosts->load($username);

    return 0 + @{ [ $vhsconf->subdomains() ] };
}

#----------------------------------------------------------------------

=head2 $resp_hr = DEL( %opts )

Deletes one of the calling user’s subdomains.

%opts are:

=over

=item * C<domain> - The full domain name to delete.

=item * C<skip_restart_apache> - boolean

=item * C<skip_phpfpm> - boolean

=item * C<force> - ???

=back

The return is a hash reference of:

=over

=item * C<message> - A human-readable message that describes what happened.
See C<Cpanel::Sub::delsubdomain()>.

=back

=cut

sub DEL ( $self, %opts ) {
    my $full_domain_name = $opts{'domain'} or die 'Need “domain”!';

    if ( $full_domain_name =~ /^www\./i ) {
        die _invalid_parameter( locale()->maketext('The system cannot change the master entry [asis,www].') );
    }

    $self->_validate_domain_ownership($full_domain_name);

    my ( $label, $the_rest ) = split m<\.>, $full_domain_name, 2;

    # REMOTE_USER needs to be set to the reseller for DNS cluster configuration
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my ( $ok, $result ) = do {
        my $redirect = Cpanel::RedirectFH->new( \*STDOUT => \*STDERR );

        Cpanel::Sub::delsubdomain(
            user       => $self->get_caller_username(),
            subdomain  => $label,
            rootdomain => $the_rest,
            %opts{ 'force', 'skip_restart_apache', 'skip_phpfpm' },
        );
    };

    if ( !$ok ) {
        die Cpanel::Exception::create( 'AdminError', [ message => $result ] );
    }

    return { message => $result };
}

=head2 $resp_hr = CHANGEDOCROOT( $FULL_DOMAIN_NAME, $NEW_DOCROOT )

Changes the given vhost’s document root. Note that $NEW_DOCROOT
will be massaged, so the actual document root that gets set may not
be what gets passed in. (TODO: It would be preferable simply to reject
invalid input rather than trying to patch it up, but as of this writing
that’s out of scope for the present refactor.)

The return is a hash reference of:

=over

=item * C<message> - A human-readable message that describes what happened.
See C<Cpanel::Sub::change_doc_root()>. This may be undef.

=back

=cut

sub CHANGEDOCROOT ( $self, $full_domain_name, $dir ) {

    _validate_dir_or_die($dir);

    $self->_validate_domain_ownership($full_domain_name);

    # REMOTE_USER needs to be set to the reseller for DNS cluster configuration
    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();

    my ( $status, $result ) = do {
        my $redirect = Cpanel::RedirectFH->new( \*STDOUT => \*STDERR );

        Cpanel::Sub::change_doc_root(
            user         => $self->get_caller_username(),
            domain       => $full_domain_name,
            documentroot => $dir,
        );
    };

    die "change docroot ($full_domain_name) => [$dir]: $result" if !$status;

    require Cpanel::PHP::Vhosts;
    require Cpanel::PHP::Config;

    # Check if the subdomain has been setup with php-fpm
    my $version_ref = Cpanel::PHP::Vhosts::get_php_vhost_versions_from_php_config( Cpanel::PHP::Config::get_php_config_for_domains_consider_addons( [$full_domain_name] ) );

    # If it has, it will need its php-fpm config file needs to be rebuilt so as
    # to contain the new document root directory
    if ( $version_ref->[0]{'php_fpm'} ) {
        require Cpanel::PHPFPM::Constants;
        require Cpanel::PHPFPM::RebuildQueue::Adder;
        require Cpanel::ServerTasks;

        Cpanel::PHPFPM::RebuildQueue::Adder->add($full_domain_name);
        Cpanel::ServerTasks::schedule_task( ['PHPFPMTasks'], $Cpanel::PHPFPM::Constants::delay_for_rebuild, 'rebuild_fpm' );
    }

    return { message => $result };
}

#----------------------------------------------------------------------

sub _get_cpuser_data ($self) {
    return Cpanel::Config::LoadCpUserFile::load_or_die( $self->get_caller_username() );
}

sub _get_REMOTE_USER ($self) {
    return $self->_get_cpuser_data()->{'OWNER'} || 'root';
}

sub _die_if_equals_hostname ($value) {
    my $hostname = Cpanel::Hostname::gethostname() || 'localhost';

    $hostname = lc $hostname;

    if ( $value eq $hostname ) {
        die _invalid_parameter("You cannot create a subdomain with the same name as the hostname of this machine ($hostname).");
    }

    return;
}

sub _invalid_parameter ($message) {
    return Cpanel::Exception::create(
        'AdminError',
        [
            class   => 'Cpanel::Exception::InvalidParameter',
            message => $message,
        ],
    );
}

sub _validate_domain_or_die ($domain) {
    my $invalid = ( $domain =~ tr<A-Z><> );

    $invalid ||= ( $domain =~ m<\s> );

    $invalid ||= ( 0 == rindex( $domain, '.', 0 ) );

    if ($invalid) {

        # This should have been validated prior to here, so there should be
        # no real harm in returning an untranslated error.
        die _invalid_parameter("Invalid: “$domain”");
    }

    return;
}

sub _validate_domain_ownership ( $self, $domain ) {

    my $user = $self->get_caller_username();

    if ( Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain) ne $user ) {
        die Cpanel::Exception->create( 'The domain “[_1]” does not belong to “[_2]”.', [ $domain, $user ] );
    }

    return 1;
}

sub _validate_dir_or_die ($dir) {
    Cpanel::Try::try(
        sub { Cpanel::Validate::DocumentRoot::validate_subdomain_document_root_characters_or_die($dir) },
        'Cpanel::Exception::InvalidParameter' => sub {
            die _invalid_parameter( $@->get_string() );
        },
    );

    return;
}

1;
