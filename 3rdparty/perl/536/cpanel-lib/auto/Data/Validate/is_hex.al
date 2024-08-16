# NOTE: Derived from blib/lib/Data/Validate.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate;

#line 291 "blib/lib/Data/Validate.pm (autosplit into blib/lib/auto/Data/Validate/is_hex.al)"
# -------------------------------------------------------------------------------


sub is_hex {
	my $self = shift if ref($_[0]); 
	my $value = shift;
	
	return unless defined $value;
	
	return if $value =~ /[^0-9a-f]/i;
	$value = lc($value);
	
	my $int = hex($value);
	return unless (defined $int);
	my $hex = sprintf "%x", $int;
	return $hex if ($hex eq $value);
	
	# handle zero stripping
	if (my ($z) = $value =~ /^(0+)/) {
		return "$z$hex" if ("$z$hex" eq $value);
	}
	
	return;
}

# end of Data::Validate::is_hex
1;
