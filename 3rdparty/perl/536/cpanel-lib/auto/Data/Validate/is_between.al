# NOTE: Derived from blib/lib/Data/Validate.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate;

#line 417 "blib/lib/Data/Validate.pm (autosplit into blib/lib/auto/Data/Validate/is_between.al)"
# -------------------------------------------------------------------------------


sub is_between{
	my $self = shift if ref($_[0]);
	my $value = shift;
	my $min = shift;
	my $max = shift;
	
	# must be a number
	my $untainted = is_numeric($value);
	return unless defined($untainted);
	
	# issues with very large numbers.  Fall over to using 
	# arbitrary precisions math.
	if(length($value) > 10){
		
		my $i = Math::BigInt->new($value);
		
		# minimum bound
		if(defined($min)){
			$min = Math::BigInt->new($min);
			return unless $i >= $min;
		}
		
		# maximum bound
		if(defined($max)){
			$max = Math::BigInt->new($max);
			return unless $i <= $max;
		}
		
		# untaint
		($value) = $i->bstr() =~ /(.+)/;
		return $value;
	}
	
	
	# minimum bound
	if(defined($min)){
		return unless $value >= $min;
	}
	
	# maximum bound
	if(defined($max)){
		return unless $value <= $max;
	}
	
	return $untainted;
}

# end of Data::Validate::is_between
1;
