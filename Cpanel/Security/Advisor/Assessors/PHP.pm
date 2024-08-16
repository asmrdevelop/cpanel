package Cpanel::Security::Advisor::Assessors::PHP;

# cpanel - Cpanel/Security/Advisor/Assessors/PHP.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use base 'Cpanel::Security::Advisor::Assessors';
use Cpanel::Result ();

my $php_ver_regex = '^ea-php(\d{2,3})$';

sub generate_advice {
    my ($self) = @_;
    $self->_check_for_php_eol();
    return 1;
}

sub _check_for_php_eol {
    my $self = shift;
    require Cpanel::API::EA4;
    require Cpanel::ProgLang;

    my $installed_php_versions = Cpanel::ProgLang->new( type => 'php' )->get_installed_packages();

    my $result = Cpanel::Result->new();
    Cpanel::API::EA4::get_recommendations( undef, $result );
    my $reco_data = $result->{'data'} if $result;

    my @reco_keys_to_consider = ();
    foreach my $installed_version (@$installed_php_versions) {
        if ( grep { $_ eq $installed_version } keys %$reco_data ) {
            push @reco_keys_to_consider, $installed_version;
        }
    }

    my @eol_php_versions = ();
    my $eol_reco_data;
    foreach my $key ( sort @reco_keys_to_consider ) {
        my @recos = @{ $reco_data->{$key} };
        foreach my $reco (@recos) {
            if ( grep { $_ eq 'eol' } @{ $reco->{'filter'} } ) {

                # Recommendation data is same for all EOL PHP versions. Storing only one such instance
                # here to use later in the advice.
                $eol_reco_data = $reco if ( !$eol_reco_data );
                push @eol_php_versions, _get_readable_php_version_format($key);
            }
        }
    }

    # Return if there is no EOL PHPs.
    return if scalar @eol_php_versions == 0;

    my $security_advisor_obj = $self->{'security_advisor_obj'};

    $security_advisor_obj->add_advice(
        {
            'key'        => 'Php_versions_going_eol',
            'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
            'text'       => $self->_lh->maketext( '[list_and,_1] reached [output,acronym,EOL,End of Life][comment,title]', \@eol_php_versions ),
            'suggestion' => _make_unordered_list( map { $_->{'text'} } @{ $eol_reco_data->{'options'} } ) . $self->_lh->maketext(
                'We recommend that you use the [output,url,_1,MultiPHP Manager,_4,_5] interface to upgrade your domains to a supported version. Then, uninstall [numerate,_2,this version,these versions] in the [output,url,_3,EasyApache 4,_4,_5] interface.',
                $self->base_path('scripts7/multiphp-manager'),
                scalar @eol_php_versions,
                $self->base_path('scripts7/EasyApache4'),
                'target',
                '_blank'
              )
              . ' '
              . $self->_lh->maketext( 'For more information, read [output,url,_1,PHP EOL Documentation,target,_blank].', 'https://www.php.net/supported-versions.php' ),
        }
    );

    return 1;
}

sub _get_readable_php_version_format {
    my ($php_version) = @_;
    my $readable_php_version;
    if ( $php_version =~ /$php_ver_regex/ ) {
        my $second_part = $1;
        $second_part =~ s/(\d)$/\.$1/;
        $readable_php_version = "PHP $second_part";
    }
    return $readable_php_version;
}

sub _make_unordered_list {
    my (@items) = @_;

    my $output = '<ul>';
    foreach my $item (@items) {
        $output .= "<li>$item</li>";
    }
    $output .= '</ul>';

    return $output;
}

1;
