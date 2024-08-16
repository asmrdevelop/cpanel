package Cpanel::API::SiteTemplates;

# cpanel - Cpanel/API/SiteTemplates.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::API::DomainInfo ();
use Cpanel::JSON            ();
use Cpanel::Logger          ();
use Cpanel::SafeDir::MK     ();
use Cpanel::SafeRun::Object ();
use Cpanel::SiteTemplates   ();
use Cpanel::JSON::Sanitize  ();

our %API = (
    _needs_role    => 'WebServer',
    _needs_feature => 'sitepublisher',
);

our $VERSION = '1.0';
my $logger = Cpanel::Logger->new();

=head1 SUBROUTINES

=over 4

=item list_site_templates()

Get a list of site templates available to the user.

This is literally just listing through the directories that should contain site templates.

input: none

return: array of available site templates

=cut

sub list_site_templates {
    my ( $args, $result ) = @_;

    $result->data( Cpanel::SiteTemplates::list_site_templates($Cpanel::user) );

    return 1;
}

=item list_user_settings()

Get current template settings for user domains.

input: none

return: a hash. The keys are user domains, and values are current settings for each domain.

=cut

sub list_user_settings {
    my ( $args, $result ) = @_;

    my $data = Cpanel::API::DomainInfo::_get_all_domains_data();

    my @list_domains = ();
    push @list_domains, $data->{'main_domain'};
    push @list_domains, @{ $data->{'addon_domains'} };
    push @list_domains, @{ $data->{'sub_domains'} };

    my $template_settings = Cpanel::SiteTemplates::list_user_settings($Cpanel::user);

    my %desired_keys = map { $_ => 1 } (qw/domain documentroot homedir serveralias type/);
    foreach my $domain (@list_domains) {
        foreach my $k ( keys %{$domain} ) {
            delete $domain->{$k} unless $desired_keys{$k};
            if ( $k eq 'serveralias' && $domain->{$k} ) {
                $domain->{$k} = [ split( /\s+/, $domain->{$k} ) ];
            }
        }

        if ( $template_settings->{ $domain->{domain} } ) {
            $domain->{'template_settings'} = $template_settings->{ $domain->{domain} };
        }
        else {
            $domain->{'template_settings'} = {};
        }
    }

    $result->data( \@list_domains );

    return 1;
}

=item publish()

Create static site documents from the template using user settings

input: a hash

return: none

=cut

sub publish {
    my ( $args, $result ) = @_;

    my $target = $args->get('target');
    $target ||= $args->get('docroot');
    unless ( $target && -d $target ) {
        $result->error("No target directory specified");
        return;
    }

    my $source = $args->get('source');
    $source ||= $args->get('path') . '/' . $args->get('template');
    unless ( $source && -d $source ) {
        $result->error("No source directory specified");
        return;
    }

    my $parameters = {};
    foreach my $k ( $args->keys() ) {
        next unless $k;
        next if $k eq 'cache-fix';
        $parameters->{$k} = $args->get($k);
    }

    my $data_file = time() . '-' . $$;
    {
        my $config_dir = $Cpanel::homedir . '/site_publisher/configurations';
        unless ( -d $config_dir ) {
            Cpanel::SafeDir::MK::safemkdir($config_dir);
        }
        chmod 0700, $config_dir;

        my $orig_mask = umask 0077;

        $data_file .= '.json';
        $data_file = $config_dir . '/' . $data_file;

        my $out_fh;
        unless ( open( $out_fh, '>', $data_file ) ) {
            $result->error( "The system could not save settings to the file: [_1].", $data_file );
            return;
        }

        print {$out_fh} Cpanel::JSON::Dump( Cpanel::JSON::Sanitize::sanitize_for_dumping($parameters) );
        close $out_fh;
        umask $orig_mask;
    }

    $logger->info( 'SiteTemplates::publish' . ':' . $parameters->{'path'} . ':' . $parameters->{'template'} . ':' . $target );

    my $cmd = _get_publish_command();
    my $ret = eval {
        Cpanel::SafeRun::Object->new_or_die(
            'program' => $cmd,
            'args'    => [
                '--target=' . $target,
                '--source=' . $source,
                '--config=' . $data_file
            ]
        );
        1;
    };

    unlink $data_file;

    if ( !$ret ) {
        $result->raw_error( $@->to_string() );
        return;
    }

    return 1;
}

sub _get_publish_command {
    return '/usr/local/cpanel/scripts/process_site_templates';
}

=back

=cut

1;
