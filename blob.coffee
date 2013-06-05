class Blob
  constructor: (@environment, @id, @energy=0, @geneCode) -> 
    @age = 0
    @id += '' #coerce to string to avoid equality issues
    @geneCode ?= new GeneCode()
    @pho = @geneCode.pho
    @atk = @geneCode.atk
    @spd = @geneCode.spd
    @eff = @geneCode.eff
    @efficiencyFactor = 1 - @eff / 100
    @energyPerSecond  = @pho * C.PHO_EPS
    @energyPerSecond += @atk * C.ATK_EPS * @efficiencyFactor
    @energyPerSecond += @spd * C.SPD_EPS * @efficiencyFactor
    @attackPower = @atk*@atk
    @currentHeading = null
    @maxMovement = @spd * C.MOVEMENT_SPEED_FACTOR
    @rad = Math.sqrt(@energy) * C.RADIUS_FACTOR + C.RADIUS_CONSTANT # Duplicated in wrap-up
    @radSq = @rad*@rad
    @stepsUntilNextAction = 0 
    @stepsUntilNextQuery = 0
    @alive = on
    @ageOfLastMove = 0
    @neighborDists = {}

  preStep: () ->
    """One full step of simulation for this blob.
    Attackables: Everything which is adjacent and close enough to 
    auto-attack. These are passed by the environment"""
    @attackedThisTurn = {}
    @attackEnergyThisTurn = 0
    @numAttacks = 0
    @movedThisTurn = off

    @energy += @energyPerSecond
    @age++
    @energyPerSecond -= C.AGE_ENERGY_DECAY
    @energy *= (1-C.ENERGY_DECAY)
    """Neighbors: Everything within seeing distance. Represented as
    list of blobs. Querying only once every 10 steps, so force-recalc
    distance for each neighbor everytime."""
    if @stepsUntilNextQuery <= 0
      @neighbors = @environment.getNeighbors(@id) 
      @stepsUntilNextQuery = 10
    else
      @neighbors = (n for n in @neighbors when n.alive)
      @stepsUntilNextQuery--
    # Return list of blobs
    
  getObservables: () ->
    for n in @neighbors
      unless @neighborDists[n.id]? and @neighborDists[n.id][1] == n.ageOfLastMove
        @neighborDists[n.id] = [@environment.blobDist(@,n), n.ageOfLastMove]
    ([n, @neighborDists[n.id][0]] for n in @neighbors)

  chooseAction: () -> 
    if @maintainCurrentAction > 0
      if @action.type == "hunt" and not @environment.isAlive(@huntTarget.id)
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
      @maintainCurrentAction = C.REPR_TIME_REQUIREMENT
      @reproducing = on

    # reproduction maintenance is handled in reproduction code
    # -1 signals to repr code to check viability and put timeline if viable
    # this is so that if a cell 

  handleMovement: () ->
    if @action.type is "hunt"
      if @action.argument?
        # Let's set heading as the vector pointing towards target 
        [targetBlob, distance] = @action.argument 
        heading = @environment.getHeading(@id, targetBlob.id)
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
      heading = @environment.getHeading(@id, targetBlob.id)
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
          # @attackedThisTurn[aBlob.id] = on
          @numAttacks++
          aBlob.numAttacks++
          # I attack them
          amt = Math.min(attackDelta, aBlob.energy)
          if @observed? or aBlob.observed? 
            console.log "#{@id} attacking #{aBlob.id} for #{amt}"

          @energy += amt
          @attackEnergyThisTurn += amt
          aBlob.energy -= attackDelta + 5
          aBlob.attackEnergyThisTurn -= attackDelta + 5
    if isNaN(@attackEnergyThisTurn)
      console.log @
      throw new Error("NAN attack energy")

  wrapUp: () -> 
    if @action.type is "repr"
      if @maintainCurrentAction == 0
        @reproduce(@action.argument)
        @reproducing = null

    @rad = Math.sqrt(@energy) * C.RADIUS_FACTOR + C.RADIUS_CONSTANT # Radius of the blob
    @radSq = @rad*@rad
    #duplicated in constructor
    if @energy < 0
      @environment.removeBlob(@id)
      @alive = off


  move: (heading, moveAmt) ->
    moveAmt = Math.min(moveAmt, @maxMovement, @energy * C.MOVEMENT_PER_ENERGY / @efficiencyFactor)
    moveAmt = Math.max(moveAmt, 0) # in case @energy is negative due to recieved attacks
    @energy -= moveAmt * @efficiencyFactor / C.MOVEMENT_PER_ENERGY
    @environment.moveBlob(@id, heading, moveAmt)
    @neighborDists = {}

  reproduce: (childEnergy) ->
    if @energy <= C.REPR_ENERGY_COST
      @energy -= C.REPR_ENERGY_COST / 2 
      return
    if childEnergy > (@energy-C.REPR_ENERGY_COST)/2
      @energy -= C.REPR_ENERGY_COST / 2
      return
    if @energy >= childEnergy + C.REPR_ENERGY_COST * @efficiencyFactor
      @energy  -= childEnergy + C.REPR_ENERGY_COST * @efficiencyFactor
      childGenes = GeneCode.copy(@geneCode)
      @environment.addChildBlob(@id, childEnergy, childGenes)
