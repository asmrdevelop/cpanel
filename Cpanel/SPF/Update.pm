package Cpanel::SPF::Update;

# cpanel - Cpanel/SPF/Update.pm                    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

my $UPDATE_BATCH_SIZE = 256;

use Cpanel::SPF::String            ();
use Cpanel::NAT                    ();
use Cpanel::DIp::Mail              ();
use Cpanel::Config::HasCpUserFile  ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::DIp::MainIP            ();
use Cpanel::DnsUtils::Install      ();

=encoding utf-8

=head1 NAME

Cpanel::SPF::Update - Update SPF records to include what the system expects

=head1 SYNOPSIS

    use Cpanel::SPF::Update;

    Cpanel::SPF::Update::update_spf_records( 'users' => [$user, ...] );

=head2 update_spf_records('users' => $users_ar, 'reload' => (0|1))

Update the SPF records for the given users
to include what the system expects them to have.

The optional 'reload' parameter indicates whether to reload zones and defaults to 1.

=cut

sub update_spf_records {
    my %OPTS   = @_;
    my @users  = @{ $OPTS{'users'} };
    my $reload = $OPTS{'reload'} // 1;

    my @DOMAINS;
    for (@users) {
        next if !Cpanel::Config::HasCpUserFile::has_cpuser_file($_);
        my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($_);
        next if ( !UNIVERSAL::isa( $cpuser_ref, 'HASH' ) || !$cpuser_ref->{'HASSPF'} );
        push @DOMAINS, $cpuser_ref->{'DOMAIN'};
        if ( ref $cpuser_ref->{'DOMAINS'} eq 'ARRAY' ) {
            push @DOMAINS, @{ $cpuser_ref->{'DOMAINS'} };
        }
    }

    @DOMAINS = grep { index( $_, '*' ) == -1 } @DOMAINS;

    return update_spf_records_for_domains( 'domains' => \@DOMAINS, 'reload' => $reload );
}

=head2 update_spf_records_for_domains('domains' => $domains_ar, 'reload' => (0|1))

Update the SPF records for the given domains
to include what the system expects them to have.

The optional 'reload' parameter indicates whether to reload zones and defaults to 1.

=cut

sub update_spf_records_for_domains {
    my %OPTS    = @_;
    my @DOMAINS = @{ $OPTS{'domains'} };
    my $reload  = $OPTS{'reload'} // 1;

    my $mainip_before_nat = Cpanel::DIp::MainIP::getmainserverip();
    my $mainip            = Cpanel::NAT::get_public_ip($mainip_before_nat);
    my $mailips           = Cpanel::DIp::Mail::loadmailips();
    require Cpanel::SPF::Include;
    my $spf_includes_ar = Cpanel::SPF::Include::get_spf_include_hosts();

    # with install_records_for_multiple_domains, the same hash ref is used for all domains
    my @installlist = (
        {
            'match'       => 'v=spf',
            'removematch' => 'v=spf',
            'domain'      => '%domain%',
            'record'      => '%domain%',
            'type'        => 'TXT',
            'operation'   => 'add',
            'value'       => Cpanel::SPF::String::make_spf_string(),    # to be used if transform is not possible because the record does not exist yet
            'domains'     => 'all',
            'transform'   => sub {
                my ( $zonefile_obj, $dnszone_entry, $template_obj ) = @_;
                my $domain = $template_obj->get_key('domain');
                my ( $mail_ips, $from_where ) = Cpanel::DIp::Mail::get_mail_ip_for_domain( $domain, $mailips );
                my @mail_ips = split( m/;\s*/, $mail_ips || '' );

                my $component = join(
                    ' ',
                    ( map { m/:/ ? "ip6:$_" : "ip4:" . Cpanel::NAT::get_public_ip($_) } grep { $_ ne $mainip_before_nat } @mail_ips ),
                    ( map { "include:$_" } @$spf_includes_ar ),
                );

                my %items_we_are_about_to_add = map { $_ => 1, "+$_" => 1 } ( "ip4:$mainip", split( m{\s+}, $component ) );
                my $old_record                = $zonefile_obj->get_zone_record_value($dnszone_entry);
                if ( $old_record =~ m{v=spf1 } ) {
                    $old_record =~ s/^\"|\"$//g;
                    my $new_record = join( ' ', grep { !$items_we_are_about_to_add{$_} } split( m{\s+}, $old_record ) );
                    $new_record =~ s/v=spf1 /v=spf1 ip4:$mainip $component /g;
                    $new_record =~ s{\s+}{ }g;
                    $zonefile_obj->set_zone_record_value( $dnszone_entry, $new_record );
                }
                return 1;
            },
        }
    );

    return Cpanel::DnsUtils::Install::install_records_for_multiple_domains(
        records => \@installlist,
        domains => { map { $_ => 'all' } @DOMAINS },
        reload  => $reload,
    );
}

# broken out from scripts/mainipcheck

=head2 update_all_users_spf_records()

Batches calls to update_spf_records() for all cPanel
users.

=cut

sub update_all_users_spf_records {
    require Cpanel::Config::Users;
    my @users = sort { $a cmp $b } Cpanel::Config::Users::getcpusers();
    while ( my @set = splice @users, 0, $UPDATE_BATCH_SIZE ) {
        Cpanel::SPF::Update::update_spf_records( 'users' => \@set );
    }
    return 1;
}
1;
