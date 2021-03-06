class Blob
  constructor: (@simulation, @id, @energy=0, @geneCode, @pos) ->
    @age = 0
    @id += '' #coerce to string to avoid equality issues
    @geneCode ?= new GeneCode()
    @pho = @geneCode.pho
    @atk = @geneCode.atk
    @spd = @geneCode.spd
    @eff = @geneCode.eff


    @red = @atk * 2.55
    @grn = @pho * 2.55
    @blu = @spd * 2.55

    # #nucleus colors
    # @red = @geneCode.red
    # @grn = @geneCode.grn
    # @blu = @geneCode.blu

    @currentHeading = null
    @maxMovement = @spd * self.C.MOVEMENT_SPEED_FACTOR
    @reproSpeedFactor = (100 - @spd) / 100
    @stepsUntilNextAction = 0
    @stepsUntilNextQuery = 0
    @alive = on
    @neighborDists = {}
    @calculateEnergyAndRadius()

  calculateEnergyAndRadius: () ->
    @efficiencyFactor = 1 - (@eff / 100) * .75
    @energyPerSecond  =  @pho * (@pho * self.C.PHO_SQ_EPS + self.C.PHO_EPS)
    @energyPerSecond -= (@atk * (@atk * self.C.ATK_SQ_EPS + self.C.ATK_EPS)) * @efficiencyFactor
    @energyPerSecond += @spd * self.C.SPD_EPS * @efficiencyFactor
    @energyPerSecond -= self.C.AGE_ENERGY_DECAY * @age * @age
    @attackPower = @atk*@atk
    @calculateRadius()

  calculateRadius: () ->
    @rad = Math.sqrt(@energy) * self.C.RADIUS_FACTOR + self.C.RADIUS_CONSTANT
    @rad *= self.C.BLOB_SIZE


  preStep: () ->
    """One full step of simulation for this blob.
    Attackables: Everything which is adjacent and close enough to
    auto-attack. These are passed by the simulation"""
    @attackedThisTurn = {}
    @attackEnergyThisTurn = 0
    @numAttacks = 0
    @movedLastTurn = @movedThisTurn
    @movedThisTurn = 0

    @energy += @energyPerSecond
    @age++
    @energy *= (1-self.C.ENERGY_DECAY)
    """Neighbors: Everything within seeing distance. Represented as
    list of blobs. Querying only once every 10 steps, so force-recalc
    distance for each neighbor everytime."""
    if @stepsUntilNextQuery <= 0
      @neighbors = @simulation.getNeighbors(@id)
      @stepsUntilNextQuery = 10
    else
      @neighbors = (n for n in @neighbors when n.alive)
      @stepsUntilNextQuery--
    # Return list of blobs

  getObservables: () ->
    for n in @neighbors
      if @neighborDists[n.id]?
        [dist, move_so_far] = @neighborDists[n.id]
        move_so_far += @movedLastTurn + n.movedLastTurn
        if move_so_far > self.C.MOVE_UPDATE_AMT
          delete @neighborDists[n.id]

      @neighborDists[n.id] ?= [@simulation.blobDist(@,n), 0]

    ([n, @neighborDists[n.id][0]] for n in @neighbors)

  chooseAction: () ->
    if @maintainCurrentAction > 0
      if @action.type == "hunt" and not @simulation.isAlive(@huntTarget.id)
        #when a target dies, stop hunting it and do something else
        @maintainCurrentAction = 0
      else
        @maintainCurrentAction--
        return

    @action = @geneCode.chooseAction(@energy, @getObservables())
    if @action.type == "hunt"
      if @huntTarget
        @huntTarget = @action.argument[0]
        @maintainCurrentAction = 20 # keep hunting same target for 20 turns
    if @action.type == "repr"
      # Blob will not do anything for a certain number of turns while it prepares to reproduce
      @maintainCurrentAction = Math.round(self.C.REPR_TIME_REQUIREMENT * @reproSpeedFactor + Math.random())
      @reproducing = on

    # reproduction maintenance is handled in reproduction code
    # -1 signals to repr code to check viability and put timeline if viable
    # this is so that if a cell

  handleMovement: () ->
    if @action.type is "hunt"
      if @action.argument?
        # Let's set heading as the vector pointing towards target
        [targetBlob, distance] = @action.argument
        heading = @simulation.getHeading(@id, targetBlob.id)
        moveAmt = distance - 3 #will be further constrained by avail. energy and speed
        @wandering = null
      else
        # If we don't have a current heading, set it randomly
        # This way hunters move randomly but with determination when
        # looking for prey
        # Conversely if they just lost sight of their prey they will
        # keep in the same direction
        @wandering ?= Vector2D.randomHeading()
        heading = @wandering
        moveAmt = @maxMovement

    else if @action.type is "flee" and @action.argument?
      [targetBlob, distance] = @action.argument
      heading = @simulation.getHeading(@id, targetBlob.id)
      heading = Vector2D.negateHeading(heading)
      moveAmt = @maxMovement
      @wandering = null
      # Current implementation only flees 1 target w/ highest fear

    else # No action -> stay put
      @wandering = null

    if heading? and moveAmt?
      @move(heading, moveAmt)

  handleAttacks: () ->
    for [aBlob, dist] in @getObservables()
      if dist < @rad + aBlob.rad + 1
        attackDelta = @attackPower - aBlob.attackPower
        if attackDelta >= 0
          @numAttacks++
          aBlob.numAttacks++
          # I attack them
          amt = Math.min(attackDelta, aBlob.energy)

          @energy += amt
          @attackEnergyThisTurn += amt
          aBlob.energy -= attackDelta
          aBlob.attackEnergyThisTurn -= attackDelta + 5
        # We both lose ATTACK_BURN energy - prevent clumps from lagging the machine
        @energy -= self.C.ATTACK_BURN
    if isNaN(@attackEnergyThisTurn)
      self.postDebug @
      self.postDebug "NAN attack energy"

  wrapUp: (@pos) ->
    # hack: pass in position as an attribute so we can draw conveniently
    if @action.type is "repr"
      if @maintainCurrentAction == 0
        @reproduce(@action.argument)
        @reproducing = null

    @calculateEnergyAndRadius()
    #duplicated in constructor
    if @energy < 0 or isNaN(@energy)
      @simulation.removeBlob(@id)
      @alive = off


  move: (heading, moveAmt) ->
    moveAmt = Math.min(moveAmt, @maxMovement, @energy * self.C.MOVEMENT_PER_ENERGY / @efficiencyFactor)
    moveAmt = Math.max(moveAmt, 0) # in case @energy is negative due to recieved attacks
    @energy -= moveAmt * @efficiencyFactor / self.C.MOVEMENT_PER_ENERGY
    @simulation.moveBlob(@id, heading, moveAmt)
    @neighborDists = {}
    @movedThisTurn = moveAmt

  reproduce: (childEnergy) ->
    if @energy <= self.C.REPR_ENERGY_COST
      if self.C.HARSH_REPRODUCTION then @energy -= self.C.REPR_ENERGY_COST / 2
      return
    if childEnergy > (@energy-self.C.REPR_ENERGY_COST)/2
      if self.C.HARSH_REPRODUCTION then @energy -= self.C.REPR_ENERGY_COST / 2
      return
    if @energy >= childEnergy + self.C.REPR_ENERGY_COST * @efficiencyFactor
      @energy  -= childEnergy + self.C.REPR_ENERGY_COST * @efficiencyFactor
      childGenes = GeneCode.copy(@geneCode)
      @simulation.addChildBlob(@id, childEnergy, childGenes)
