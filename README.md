# igp

igp.rb is an interactive gnuplot program designed for easy 2D plotting of time series data from CSV files.

---

## usage:

igp.rb [csv file a] [csv file b] ... etc.

by default, the first variable from [csv file a] is plotted in a new window,
and details of all files are shown in the terminal. interactive-mode is established. 

## special x-axis (time) characters

each can have a number in front without spaces
_y_ : year
_m_ : month
_w_ : week
_d_ : day
_h_ : hour

## examples:

NOTE: Any number of these items can be used on a single line with a space between each.

_4 |6w y0,5_
plot variable 4 from each .csv file; set the time axis from start-time to 6-weeks from that; set the y-axis range from 0 to 5


### selecting variables for plotting:

_a_   
plot each variable from [csv file a]  

_a6_  
plot variable 6 from [csv file a]  

_vn_  
plot the next variable in the file

_vp_  
plot the previous variable in the file

_a3,5_    
plot variable 3 from [csv file a], and variable 5 from all csv files

_2,3_    
plot variables 2 and 3 from all csv files


### changing the x-axis (time):

_t_  
set the x-axis range to the largest extent of time

_tv_  
set the x-axis range to the overlapping time

_ta_  
set the x-axis range to the start and end times from [csv file a]

_>y_  
set the x-axis to the next full year

_3w_  
set the x-axis to 3 weeks and centered

_|2d_  
keep the start time as-is, and set the end time to 2 days from that

_6m|_  
keep the end time as-is, and set the start time to 6 months prior to that

_0.25y_  
set the x-axis range to 0.25 years and centered

_s2008-6_  
set the x-axis start time to be June 1, 2008

_s2001 e2004_  
set the x-axis range to be Jan 1, 2001 to Jan 1 2004

_>_  
move one entire time axis forward in time

_>>_  
move two whole time axes forward in time

_3<_  
move 3 whote time axes backward in time

_<>_  
expand time outward

_><_  
shrink time inward

_\<4\>_  
expand time outward, faster

_|>>_  
retain the start time, but move the end time forward

_>|_  
move the start time forward, but retain the end time

### changing the y-axis (data):

_y100,450_  
set the y-axis range from 100 to 450

_y-5_  
set the y-axis lower limit to -5

_y,85_  
set the y-axis upper limit to 85

_y_  
set the y-axis to auto-mode (this will automatically determine the y-axis limits); if the y-axis is already in auto-mode, then this will set the time axis to a centered 1-year range

### recognized options: 

_-s_  
toggle :show_cmd

_-lw=2_  
set :linewidth to 2

_-style=lp_  
set :style to linepoints

### other:

_i_  
display file info

_q_  
quit the program 

_<carriage-return>_  
do the previous command again

## assumptions about the input CSV files:

variable names must be a comma-separated list on a single line in the file,  
beginning with the word 'fields,'

the input csv file(s) time format is '%Y-%m-%d %H:%M:%S'  

any lines that begin with a non-numeric character are ignored in the input csv file(s)

