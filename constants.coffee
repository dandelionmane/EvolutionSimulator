class C
  # Environment variables
  @X_BOUND = 1000
  @Y_BOUND = 500
  @DISPLAY_BOUND = 100
  @NEIGHBOR_DISTANCE = 100
  @CHILD_DISTANCE    = 100
  @ATTACK_MARGIN     = 100
  @STARTING_ENERGY   = 200
  @HUGE_SIZE         = 400
  @STARTING_BLOBS    = 50
  
  # Blob variables
  @MOVEMENT_PER_ENERGY = 100
  @REPR_ENERGY_COST    = 600
  @MOVEMENT_SPEED_FACTOR = .1
  @PHO_EPS =  1.5
  @ATK_EPS = -2
  @SPD_EPS = 0
  @AGE_ENERGY_DECAY = .0001
  @RADIUS_FACTOR = .3
  @RADIUS_CONSTANT = 5 
  @ENERGY_DECAY = .001 # not implemented
  @REPR_TIME_REQUIREMENT = 7


  # Backend variables
  @QTREE_BUCKET_SIZE = 100
