package Cpanel::SSL::Auto::Run::DCVResult;

# cpanel - Cpanel/SSL/Auto/Run/DCVResult.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::DCVResult

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

This class encapsulates DCV results. When AutoSSL first shipped this was
a simple hash, but the addition of external DCV (for, e.g., Let’s Encrypt)
as well as DNS DCV necessitated more substantial storage/retrieval logic.

=cut

#----------------------------------------------------------------------

use Cpanel::Context        ();
use Cpanel::WildcardDomain ();

use constant METHODS => qw( master http dns );

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $OBJ = I<CLASS>->new()

Returns an instance of this class.

=cut

sub new {
    my ($class) = @_;

    return bless { _dcv => {} }, $class;
}

=head2 $OBJ2 = $OBJ->slice_for_domains( \@DOMAINS )

Returns a new instance of this class that contains results for
only the domains given in @DOMAINS.

=cut

sub slice_for_domains ( $self, $domains_ar ) {

    return $self->_slice_for_domains( $domains_ar, [] );
}

=head2 $OBJ2 = $OBJ->slice_for_domains_wc( \@DOMAINS )

Like C<slice_for_domains()>, but this will also return results
for wildcards that can substitute for one or more members of @DOMAINS.

=cut

sub slice_for_domains_wc ( $self, $domains_ar ) {

    # Facilitate wildcard reduction:
    my @wildcards = Cpanel::WildcardDomain::to_wildcards(@$domains_ar);

    return $self->_slice_for_domains( $domains_ar, \@wildcards );
}

sub _slice_for_domains {
    my ( $self, $domains_ar, $wildcards_ar ) = @_;

    my $new = ( ref $self )->new();

    my %dcv = (
        %{ $self->{'_dcv'} }{@$domains_ar},
        map { exists( $self->{'_dcv'}{$_} ) ? ( $_ => $self->{'_dcv'}{$_} ) : () } @$wildcards_ar,
    );
    $new->{'_dcv'} = \%dcv;

    return $new;
}

#----------------------------------------------------------------------

sub _add ( $self, $domain, $method, $result ) {

    die "bad method ($method)" if !grep { $_ eq $method } METHODS();

    $self->{'_dcv'}{$domain}{$method} = $result;

    return $self;
}

=head2 I<OBJ>->add_http( DOMAIN, RESULT );

Registers a I<local> HTTP DCV result. The arguments are:

=over

=item * C<DOMAIN> - the FQDN that has been DCVed

=item * C<RESULT> - The DCV result. Indicate a DCV success via undef;
anything else is considered to indicate a DCV failure. (This is probably
going to be the result of a function in L<Cpanel::SSL::Auto::Run::DCV>.)

=back

Returns I<OBJ>.

=cut

sub add_http ( $self, $domain, $result ) {
    return $self->_add( $domain, 'http', $result );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->add_dns( DOMAIN, RESULT );

Like C<add_http()> but for a local DNS DCV result.

=cut

sub add_dns ( $self, $domain, $result ) {
    return $self->_add( $domain, 'dns', $result );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->add_master( DOMAIN, RESULT );

Like C<add_http()> but for an “external” DCV result—i.e.,
DCV from the AutoSSL provider.

The provider must track DCV methods internally. An external
DCV result “trumps” an internal one, so that if external DCV fails,
then the DOMAIN is regarded as having failed DCV, even if the internal
one succeeded.

=cut

sub add_master ( $self, $domain, $result ) {
    return $self->_add( $domain, 'master', $result );
}

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->get_domains()

Returns every domain that this object knows about, unsorted.

=cut

sub get_domains {
    my ($self) = @_;

    return keys %{ $self->{'_dcv'} };
}

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->get_successful_domains()

A domain is considered “successful” if both of the following are true:

=over

=item * The C<master> method has not registered a failure.

=item * At least one other method has registered a succcess.

=back

Examples:

=over

=item * C<http> fails, C<dns> succeeds: SUCCESS

=item * C<http> fails, C<dns> succeeds, C<master> succeeds: SUCCESS

=item * C<http> fails, C<dns> succeeds, C<master> fails: FAILURE

=back

In scalar context, this returns the number of successful domains.

=cut

sub get_successful_domains {
    my ($self) = @_;

    return keys %{ $self->get_domain_success_methods() };
}

#----------------------------------------------------------------------

=head2 $domain_method_hr = I<OBJ>->get_domain_success_methods()

For each successful domain, give the method that makes it a
success. The return is a hash reference of ( $domain => $method ).

=cut

sub get_domain_success_methods {
    my ($self) = @_;

    my $dcv_hr = $self->{'_dcv'};

    my %domain_method;

    for my $domain ( keys %{ $self->{'_dcv'} } ) {
        if ( exists $dcv_hr->{$domain}{'master'} ) {
            if ( !$dcv_hr->{$domain}{'master'} ) {
                $domain_method{$domain} = 'master';
            }
        }
        else {
            for my $method ( METHODS() ) {
                next if !exists $dcv_hr->{$domain}{$method};
                if ( !defined $dcv_hr->{$domain}{$method} ) {
                    $domain_method{$domain} = $method;
                }
            }
        }
    }

    return \%domain_method;
}

#----------------------------------------------------------------------

=head2 $domain_result_hr = I<OBJ>->get_domain_failure_reasons()

For each failed domain, give the failure reasons.
The return is a hash reference, like:

    {
        $domain => [
            { method => $method, reason => $reason },
            # ..
        ],
        # ..
    }

… where $method is one of those described under C<add()> above
and $reason is a string that describes the DCV failure.

A C<dns> failure will be listed before an C<http> failure.
A C<master> failure will be alone in its array.

=cut

sub get_domain_failure_reasons {
    my ($self) = @_;

    my $dcv_hr = $self->{'_dcv'};

    my %domain_result;

  DOMAIN:
    for my $domain ( keys %{ $self->{'_dcv'} } ) {
        if ( exists $dcv_hr->{$domain}{'master'} ) {
            if ( $dcv_hr->{$domain}{'master'} ) {
                $domain_result{$domain} = [
                    {
                        method => 'master',
                        reason => $dcv_hr->{$domain}{'master'},
                    },
                ];
            }
        }
        else {

            #DNS failures will take priority over HTTP failures.
            for my $method ( METHODS() ) {
                next if !exists $dcv_hr->{$domain}{$method};

                if ( defined $dcv_hr->{$domain}{$method} ) {
                    unshift @{ $domain_result{$domain} }, {
                        method => $method,
                        reason => $dcv_hr->{$domain}{$method},
                    };
                }

                # undef reason means a success, in light of which
                # we don’t care about any failures.
                else {
                    delete $domain_result{$domain};
                    next DOMAIN;
                }
            }
        }
    }

    return \%domain_result;
}

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->get_failed_domains()

Returns either the domains (list) or their number (scalar).

=cut

sub get_failed_domains {
    my ($self) = @_;

    return keys %{ $self->get_domain_failure_reasons() };
}

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->get_dns_pending_domains()

Returns the list of domains whose I<only> registered DCV failure
is HTTP.

=cut

sub get_dns_pending_domains {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    my $dcv_reasons_hr = $self->get_domain_failure_reasons();

    my @dns_domains;

    for my $domain ( keys %$dcv_reasons_hr ) {
        next if @{ $dcv_reasons_hr->{$domain} } > 1;

        next if $dcv_reasons_hr->{$domain}[0]{'method'} ne 'http';

        push @dns_domains, $domain;
    }

    return @dns_domains;
}

1;
